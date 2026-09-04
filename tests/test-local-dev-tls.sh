#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_directory=

# shellcheck source=bootstrap/local-dev-tls.sh
source "$ROOT/bootstrap/local-dev-tls.sh"

cleanup() {
  if [[ -n "$test_directory" ]]; then
    rm -rf "$test_directory"
  fi
}

fail() {
  printf 'not ok: %s\n' "$*" >&2
  exit 1
}

issue_test_certificate() {
  local ca_value="$3"
  local certificate="$2"
  local extensions="$test_directory/leaf-extensions.cnf"
  local private_key="$1"
  local request="$test_directory/leaf-request.pem"
  local sans="$4"

  {
    printf '%s\n' '[leaf]'
    if [[ -n "$ca_value" ]]; then
      printf 'basicConstraints=critical,CA:%s\n' "$ca_value"
    fi
    printf '%s\n' \
      'keyUsage=critical,digitalSignature,keyEncipherment' \
      'extendedKeyUsage=serverAuth' \
      "subjectAltName=$sans"
  } > "$extensions"
  /usr/bin/openssl req -new -key "$private_key" -out "$request" \
    -subj /CN=localhost >/dev/null 2>&1
  /usr/bin/openssl x509 -req -in "$request" \
    -CA "$ca_root/rootCA.pem" -CAkey "$ca_root/rootCA-key.pem" \
    -CAserial "$test_directory/rootCA.srl" -CAcreateserial -days 365 \
    -extfile "$extensions" -extensions leaf -out "$certificate" >/dev/null 2>&1
}

main() {
  local air_plan
  local expected_sans
  local mkcert_log
  local personal_plan
  local work_plan

  air_plan="$("$ROOT/bin/local-dev-tls" plan air)"
  [[ -z "$air_plan" ]] || fail "the Air creates local development TLS state"

  personal_plan="$("$ROOT/bin/local-dev-tls" plan personal-mini)"
  grep -Fq 'state: enabled' <<<"$personal_plan" || fail "personal TLS is not enabled"
  grep -Fq 'bin/local-dev-tls init personal-mini' <<<"$personal_plan" \
    || fail "personal TLS commissioning command is missing"

  work_plan="$("$ROOT/bin/local-dev-tls" plan work-mini)"
  grep -Fq 'state: enabled' <<<"$work_plan" || fail "work TLS is not enabled"
  grep -Fq 'bin/local-dev-tls init work-mini' <<<"$work_plan" \
    || fail "work TLS commissioning command is missing"

  if "$ROOT/bin/local-dev-tls" init air >/dev/null 2>&1; then
    fail "TLS initialization was accepted for the Air"
  fi

  if [[ "$(uname -s)" != Darwin ]]; then
    printf 'skip: local development TLS material checks require macOS\n'
    return
  fi

  test_directory="$(mktemp -d "${TMPDIR:-/tmp}/mac-bootstrap-local-tls-test.XXXXXX")"
  HOME="$test_directory/home"
  mkdir -p "$HOME"
  load_profile work-mini
  set_paths
  mkcert_log="$test_directory/mkcert.log"
  mkcert() {
    printf 'invoked\n' >> "$mkcert_log"
    return 1
  }

  if (renew_state >/dev/null 2>&1); then
    fail "TLS renewal succeeded without initialized state"
  fi
  [[ ! -s "$mkcert_log" ]] || fail "TLS renewal created a CA before validating state"

  mkdir -p "$bundle_directory"
  chmod 700 "$tls_state_root" "$bundle_directory"
  if (renew_state >/dev/null 2>&1); then
    fail "TLS renewal succeeded without an issuing CA"
  fi
  [[ ! -s "$mkcert_log" ]] || fail "TLS renewal rotated a missing CA"
  if (initialize_state >/dev/null 2>&1); then
    fail "TLS initialization replaced the CA for an existing bundle"
  fi
  [[ ! -s "$mkcert_log" ]] || fail "TLS initialization rotated an existing bundle's CA"
  unset -f mkcert

  rm -R "$tls_state_root"
  mkdir -p "$ca_root" "$bundle_directory"
  chmod 700 "$tls_state_root" "$ca_root" "$bundle_directory"
  /usr/bin/openssl genrsa -out "$ca_root/rootCA-key.pem" 2048 >/dev/null 2>&1
  /usr/bin/openssl req -x509 -new -key "$ca_root/rootCA-key.pem" \
    -out "$ca_root/rootCA.pem" -days 800 -subj /CN=mac-bootstrap-test \
    -addext basicConstraints=critical,CA:TRUE \
    -addext keyUsage=critical,keyCertSign,cRLSign >/dev/null 2>&1
  chmod 400 "$ca_root/rootCA-key.pem"
  chmod 644 "$ca_root/rootCA.pem"

  issue_material
  replace_bundle
  /usr/bin/openssl x509 -in "$bundle_directory/localhost.pem" -noout -text \
    | grep -Fq 'CA:FALSE' || fail "issued leaf certificate lacks CA:FALSE"

  expected_sans='DNS:localhost,IP:127.0.0.1,IP:::1,DNS:dev.localhost,DNS:*.dev.localhost'

  verify_ca_state || fail "valid test CA state was rejected"
  verify_material_directory "$bundle_directory" work \
    || fail "valid TLS server material was rejected"

  chmod +a "everyone allow read" "$bundle_directory/localhost-key.pem"
  if verify_material_directory "$bundle_directory" work; then
    fail "ACL-readable leaf key was accepted"
  fi
  chmod -N "$bundle_directory/localhost-key.pem"

  issue_test_certificate "$bundle_directory/localhost-key.pem" \
    "$bundle_directory/localhost.pem" FALSE "$expected_sans,DNS:example.com"
  if verify_material_directory "$bundle_directory" work; then
    fail "leaf certificate with an extra DNS identity was accepted"
  fi

  issue_test_certificate "$bundle_directory/localhost-key.pem" \
    "$bundle_directory/localhost.pem" '' "$expected_sans"
  if verify_material_directory "$bundle_directory" work; then
    fail "leaf certificate without an explicit CA constraint was accepted"
  fi

  issue_test_certificate "$bundle_directory/localhost-key.pem" \
    "$bundle_directory/localhost.pem" TRUE "$expected_sans"
  if verify_material_directory "$bundle_directory" work; then
    fail "CA-capable leaf certificate was accepted"
  fi

  install -m 0600 "$ca_root/rootCA-key.pem" "$bundle_directory/localhost-key.pem"
  issue_test_certificate "$bundle_directory/localhost-key.pem" \
    "$bundle_directory/localhost.pem" FALSE "$expected_sans"
  if verify_material_directory "$bundle_directory" work; then
    fail "CA private key was accepted as exportable leaf material"
  fi

  printf 'ok: local development TLS profile policy\n'
}

trap cleanup EXIT
main "$@"
