#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=bootstrap/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

temporary_directory=
backup_directory=
pending_export_directory=
tls_state_root=
ca_root=
bundle_directory=
vm_profile=

cleanup() {
  if [[ -n "$backup_directory" && -d "$backup_directory" && ! -e "$bundle_directory" ]]; then
    mv "$backup_directory" "$bundle_directory"
  fi
  if [[ -n "$temporary_directory" && -d "$temporary_directory" ]]; then
    rm -R "$temporary_directory"
  fi
  if [[ -n "$pending_export_directory" \
    && ( -e "$pending_export_directory" || -L "$pending_export_directory" ) ]]; then
    rm -R "$pending_export_directory"
  fi
}

set_paths() {
  tls_state_root="$HOME/Library/Application Support/mac-bootstrap/local-dev-tls/$MAC_PROFILE"
  ca_root="$tls_state_root/ca"
  bundle_directory="$tls_state_root/bundle"
  vm_profile="${MAC_PROFILE%-mini}"
}

require_enabled_profile() {
  [[ "$MAC_LOCAL_DEV_TLS" == enabled ]] || die "Local development TLS is disabled for $MAC_PROFILE."
}

path_has_mode_and_owner() {
  local path="$1"
  local expected_mode="$2"

  [[ ! -L "$path" ]] || return 1
  [[ "$(stat -f '%u' "$path")" == "$(id -u)" ]] || return 1
  [[ "$(stat -f '%Lp' "$path")" == "$expected_mode" ]] || return 1
  path_has_no_acl "$path"
}

keys_match() {
  local certificate="$1"
  local private_key="$2"
  local certificate_public_key
  local private_public_key
  local result

  certificate_public_key="$(mktemp "${TMPDIR:-/tmp}/mac-bootstrap-cert-public.XXXXXX")"
  private_public_key="$(mktemp "${TMPDIR:-/tmp}/mac-bootstrap-key-public.XXXXXX")"
  if ! /usr/bin/openssl x509 -in "$certificate" -pubkey -noout >"$certificate_public_key" \
    || ! /usr/bin/openssl pkey -in "$private_key" -pubout >"$private_public_key" 2>/dev/null; then
    rm -f "$certificate_public_key" "$private_public_key"
    return 1
  fi
  if cmp -s "$certificate_public_key" "$private_public_key"; then
    result=0
  else
    result=1
  fi
  rm -f "$certificate_public_key" "$private_public_key"
  return "$result"
}

certificate_has_exact_sans() {
  local certificate="$1"
  local actual_sans
  local expected_sans

  actual_sans="$(/usr/bin/openssl x509 -in "$certificate" -noout -text | awk '
    /X509v3 Subject Alternative Name:/ {
      getline
      sub(/^[[:space:]]+/, "")
      print
      exit
    }
  ')" || return 1
  actual_sans="$(tr ',' '\n' <<<"$actual_sans" \
    | awk '{
        gsub(/^[[:space:]]+|[[:space:]]+$/, "")
        value = tolower($0)
        if (value == "ip address:::1") value = "ip address:0:0:0:0:0:0:0:1"
        print value
      }' \
    | LC_ALL=C sort)"
  expected_sans="$(printf '%s\n' \
    'dns:*.dev.localhost' \
    'dns:dev.localhost' \
    'dns:localhost' \
    'ip address:0:0:0:0:0:0:0:1' \
    'ip address:127.0.0.1' \
    | LC_ALL=C sort)"
  [[ "$actual_sans" == "$expected_sans" ]]
}

certificate_is_server_leaf() {
  local certificate="$1"
  local certificate_text

  certificate_text="$(/usr/bin/openssl x509 -in "$certificate" -noout -text)" || return 1
  grep -Fq 'CA:FALSE' <<<"$certificate_text" || return 1
  /usr/bin/openssl x509 -in "$certificate" -noout -purpose \
    | grep -Fqx 'SSL server : Yes'
}

verify_ca_state() {
  path_has_no_symlinked_home_components "$tls_state_root" || return 1
  path_has_no_symlinked_home_components "$ca_root" || return 1
  [[ -d "$tls_state_root" ]] && path_has_mode_and_owner "$tls_state_root" 700 || return 1
  [[ -d "$ca_root" ]] && path_has_mode_and_owner "$ca_root" 700 || return 1
  [[ -f "$ca_root/rootCA.pem" ]] && path_has_mode_and_owner "$ca_root/rootCA.pem" 644 || return 1
  [[ -f "$ca_root/rootCA-key.pem" ]] \
    && path_has_mode_and_owner "$ca_root/rootCA-key.pem" 400 || return 1
  /usr/bin/openssl x509 -in "$ca_root/rootCA.pem" -checkend 31536000 -noout >/dev/null \
    || return 1
  /usr/bin/openssl x509 -in "$ca_root/rootCA.pem" -noout -text \
    | grep -Fq 'CA:TRUE' || return 1
  keys_match "$ca_root/rootCA.pem" "$ca_root/rootCA-key.pem"
}

verify_material_directory() {
  local directory="$1"
  local expected_profile="$2"
  local entry_count

  [[ -d "$directory" ]] && path_has_mode_and_owner "$directory" 700 || return 1
  entry_count="$(find "$directory" -mindepth 1 -maxdepth 1 -print | wc -l | tr -d '[:space:]')"
  [[ "$entry_count" == 4 ]] || return 1
  [[ -f "$directory/root-ca.pem" ]] \
    && path_has_mode_and_owner "$directory/root-ca.pem" 644 || return 1
  [[ -f "$directory/localhost.pem" ]] \
    && path_has_mode_and_owner "$directory/localhost.pem" 644 || return 1
  [[ -f "$directory/localhost-key.pem" ]] \
    && path_has_mode_and_owner "$directory/localhost-key.pem" 600 || return 1
  [[ -f "$directory/profile" ]] && path_has_mode_and_owner "$directory/profile" 644 \
    || return 1
  [[ ! -e "$directory/rootCA-key.pem" && ! -L "$directory/rootCA-key.pem" ]] || return 1
  [[ "$(<"$directory/profile")" == "$expected_profile" ]] || return 1
  cmp -s "$ca_root/rootCA.pem" "$directory/root-ca.pem" || return 1
  /usr/bin/openssl verify -CAfile "$directory/root-ca.pem" "$directory/localhost.pem" \
    >/dev/null || return 1
  /usr/bin/openssl x509 -in "$directory/localhost.pem" -checkend 2592000 -noout \
    >/dev/null || return 1
  keys_match "$directory/localhost.pem" "$directory/localhost-key.pem" || return 1
  if keys_match "$ca_root/rootCA.pem" "$directory/localhost-key.pem"; then
    return 1
  fi
  certificate_is_server_leaf "$directory/localhost.pem" || return 1
  certificate_has_exact_sans "$directory/localhost.pem"
}

verify_system_trust() {
  /usr/bin/security verify-cert -c "$bundle_directory/localhost.pem" -p ssl \
    -n localhost -L -q >/dev/null 2>&1
}

verify_state() {
  if ! verify_ca_state; then
    warn "Local development CA state is missing or unsafe: $ca_root"
    return 1
  fi
  if ! verify_material_directory "$bundle_directory" "$vm_profile"; then
    warn "Local development TLS material is missing, expired or unsafe: $bundle_directory"
    return 1
  fi
  if ! verify_system_trust; then
    warn "The local development CA is not trusted by the macOS system trust store."
    return 1
  fi
}

initialize_ca() {
  local root_certificate="$ca_root/rootCA.pem"
  local root_key="$ca_root/rootCA-key.pem"
  local existing_ca=0

  require_macos
  command -v mkcert >/dev/null 2>&1 \
    || die "mkcert is not installed. Run bin/mac apply $MAC_PROFILE first."
  path_has_no_symlinked_home_components "$ca_root" \
    || die "Refusing symlinked local development TLS state."

  if [[ -e "$root_certificate" || -L "$root_certificate" \
    || -e "$root_key" || -L "$root_key" ]]; then
    [[ -f "$root_certificate" && ! -L "$root_certificate" \
      && -f "$root_key" && ! -L "$root_key" ]] \
      || die "Local development CA state is incomplete or unsafe: $ca_root"
    verify_ca_state || die "Existing local development CA state is invalid or unsafe: $ca_root"
    existing_ca=1
  else
    mkdir -p "$tls_state_root" "$ca_root"
    chmod 700 "$tls_state_root" "$ca_root"
    if ! path_has_mode_and_owner "$tls_state_root" 700 \
      || ! path_has_mode_and_owner "$ca_root" 700; then
      die "Local development TLS directories have unsafe ownership, modes or ACLs."
    fi
  fi

  CAROOT="$ca_root" TRUST_STORES=system mkcert -install
  chmod 700 "$ca_root"
  chmod 644 "$root_certificate"
  chmod 400 "$root_key"
  if ! verify_ca_state; then
    if [[ "$existing_ca" -eq 1 ]]; then
      die "mkcert changed the existing local development CA into an invalid state."
    fi
    die "mkcert produced invalid local development CA state."
  fi
}

issue_material() {
  temporary_directory="$(mktemp -d "$tls_state_root/.bundle.XXXXXX")"
  chmod 700 "$temporary_directory"

  CAROOT="$ca_root" mkcert \
    -cert-file "$temporary_directory/localhost.pem" \
    -key-file "$temporary_directory/localhost-key.pem" \
    localhost 127.0.0.1 ::1 dev.localhost '*.dev.localhost'
  install -m 0644 "$ca_root/rootCA.pem" "$temporary_directory/root-ca.pem"
  printf '%s\n' "$vm_profile" >"$temporary_directory/profile"
  chmod 0644 "$temporary_directory/profile"
  verify_material_directory "$temporary_directory" "$vm_profile" \
    || die "Generated local development TLS material failed validation."
}

replace_bundle() {
  if [[ -e "$bundle_directory" || -L "$bundle_directory" ]]; then
    [[ -d "$bundle_directory" && ! -L "$bundle_directory" ]] \
      || die "Refusing unsafe TLS bundle path: $bundle_directory"
    backup_directory="$tls_state_root/.bundle.previous.$$"
    [[ ! -e "$backup_directory" ]] \
      || die "Temporary TLS backup already exists: $backup_directory"
    mv "$bundle_directory" "$backup_directory"
  fi

  mv "$temporary_directory" "$bundle_directory"
  temporary_directory=
  if [[ -n "$backup_directory" ]]; then
    rm -R "$backup_directory"
    backup_directory=
  fi
}

initialize_state() {
  if [[ -e "$bundle_directory" || -L "$bundle_directory" ]]; then
    [[ -d "$bundle_directory" && ! -L "$bundle_directory" ]] \
      || die "Existing TLS bundle path is unsafe: $bundle_directory"
    verify_ca_state \
      || die "Existing TLS bundle has no valid issuing CA; refusing to create or rotate it."
  fi
  initialize_ca
  if [[ -e "$bundle_directory" || -L "$bundle_directory" ]]; then
    verify_state || die "Existing TLS state is invalid; inspect it before running renew."
    info "Local development TLS is already initialized for $MAC_PROFILE"
    return
  fi
  issue_material
  replace_bundle
  verify_state || die "Local development TLS initialization failed verification."
  info "Initialized and trusted local development TLS for $MAC_PROFILE"
}

renew_state() {
  [[ -d "$bundle_directory" && ! -L "$bundle_directory" ]] \
    || die "Local development TLS is not initialized for $MAC_PROFILE."
  verify_ca_state \
    || die "Local development TLS has no valid issuing CA; refusing to rotate it."
  initialize_ca
  issue_material
  replace_bundle
  verify_state || die "Renewed local development TLS failed verification."
  info "Renewed local development TLS for $MAC_PROFILE"
}

export_bundle() {
  local destination="$1"

  verify_state || die "Local development TLS must verify before export."
  [[ ! -e "$destination" && ! -L "$destination" ]] \
    || die "Export destination already exists: $destination"
  mkdir -m 0700 "$destination"
  pending_export_directory="$destination"
  path_has_mode_and_owner "$destination" 700 \
    || die "Export destination has unsafe ownership, mode or ACLs: $destination"
  install -m 0644 "$bundle_directory/root-ca.pem" "$destination/root-ca.pem"
  install -m 0644 "$bundle_directory/localhost.pem" "$destination/localhost.pem"
  install -m 0600 "$bundle_directory/localhost-key.pem" "$destination/localhost-key.pem"
  install -m 0644 "$bundle_directory/profile" "$destination/profile"
  verify_material_directory "$destination" "$vm_profile" \
    || die "Exported VM TLS handoff failed validation."
  pending_export_directory=
  info "Exported VM TLS handoff to $destination"
  warn "The handoff contains a private leaf key; remove it after VM import."
}

plan_state() {
  [[ "$MAC_PROFILE_KIND" == mini ]] || return 0
  printf '\nLocal development TLS:\n'
  printf 'state: %s\n' "$MAC_LOCAL_DEV_TLS"
  if [[ "$MAC_LOCAL_DEV_TLS" == enabled ]]; then
    printf 'CA and leaf state: %s\n' "$tls_state_root"
    printf 'commissioning: bin/local-dev-tls init %s\n' "$MAC_PROFILE"
  fi
}

usage() {
  cat <<'USAGE'
Usage:
  local-dev-tls plan PROFILE
  local-dev-tls init PROFILE
  local-dev-tls renew PROFILE
  local-dev-tls verify PROFILE
  local-dev-tls export PROFILE DESTINATION
USAGE
}

main() {
  local command="${1:-}"
  local profile="${2:-}"

  case "$command" in
    plan|init|renew|verify)
      [[ $# -eq 2 ]] || { usage >&2; exit 1; }
      ;;
    export)
      [[ $# -eq 3 ]] || { usage >&2; exit 1; }
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac

  load_profile "$profile"
  set_paths

  case "$command" in
    plan)
      plan_state
      ;;
    init)
      require_enabled_profile
      initialize_state
      ;;
    renew)
      require_enabled_profile
      renew_state
      ;;
    verify)
      require_enabled_profile
      require_macos
      verify_state
      ;;
    export)
      require_enabled_profile
      require_macos
      export_bundle "$3"
      ;;
  esac
}

trap cleanup EXIT
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
