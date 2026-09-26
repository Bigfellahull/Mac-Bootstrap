#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_directory=

# shellcheck source=bootstrap/orbstack-docker-api.sh
source "$ROOT/bootstrap/orbstack-docker-api.sh"

cleanup() {
  if [[ -n "$test_directory" ]]; then
    rm -rf "$test_directory"
  fi
}

fail() {
  printf 'not ok: %s\n' "$*" >&2
  exit 1
}

main() {
  local authorized_keys
  local marker=orbstack-docker-api-work-mini
  local personal_plan
  local public_key
  local test_home
  local work_plan

  work_plan="$("$ROOT/bootstrap/orbstack-docker-api.sh" plan work-mini)"
  grep -Fq 'state: disabled' <<<"$work_plan" || fail "work bridge is not disabled by default"

  personal_plan="$("$ROOT/bootstrap/orbstack-docker-api.sh" plan personal-mini)"
  grep -Fq 'state: disabled' <<<"$personal_plan" || fail "personal bridge is not disabled"

  [[ -z "$("$ROOT/bootstrap/orbstack-docker-api.sh" plan air)" ]] || \
    fail "the Air exposes an OrbStack Docker API bridge"

  if [[ "$(uname -s)" != Darwin ]]; then
    printf 'skip: authorization checks require macOS\n'
    return
  fi

  test_directory="$(mktemp -d "${TMPDIR:-/tmp}/mac-bootstrap-orbstack-api-test.XXXXXX")"
  HOME="$test_directory"
  mkdir -p "$HOME/.config/mac-bootstrap"
  for role in work-mini personal-mini; do
    printf 'enabled\n' > "$HOME/.config/mac-bootstrap/docker-api-bridge.$role"
    chmod 600 "$HOME/.config/mac-bootstrap/docker-api-bridge.$role"
    plan="$(HOME="$HOME" "$ROOT/bootstrap/orbstack-docker-api.sh" plan "$role")"
    grep -Fq 'state: enabled' <<<"$plan" || fail "$role opt-in ignored"
    grep -Fq "orbstack-docker-api-$role" <<<"$plan" || fail "$role marker missing"
    printf 'invalid\n' > "$HOME/.config/mac-bootstrap/docker-api-bridge.$role"
    if HOME="$HOME" "$ROOT/bootstrap/orbstack-docker-api.sh" plan "$role" >/dev/null 2>&1; then fail "invalid policy accepted"; fi
    rm "$HOME/.config/mac-bootstrap/docker-api-bridge.$role"
  done
  authorized_keys="$test_directory/authorized_keys"
  ssh-keygen -q -t ed25519 -N '' -C bridge-test -f "$test_directory/bridge-key"
  public_key="$(awk '{ print $1, $2 }' "$test_directory/bridge-key.pub")"
  printf '%s %s %s\n' \
    'restrict,port-forwarding,command="/usr/bin/false"' "$public_key" "$marker" \
    > "$authorized_keys"
  chmod 600 "$authorized_keys"

  authorization_is_restricted "$authorized_keys" "$marker" || \
    fail "safe authorization was rejected"
  load_profile work-mini
  printf '%s %s %s\n' \
    'restrict,port-forwarding,command="/usr/bin/false"' "$public_key" \
    orbstack-docker-api-personal-mini >> "$authorized_keys"
  foreign_authorization_exists || fail "other-profile authorization was not detected"
  printf '%s %s %s\n' \
    'restrict,port-forwarding,command="/usr/bin/false"' "$public_key" "$marker" \
    > "$authorized_keys"

  printf '%s %s %s\n' \
    'restrict,port-forwarding,pty,command="/usr/bin/false"' "$public_key" "$marker" \
    > "$authorized_keys"
  if authorization_is_restricted "$authorized_keys" "$marker"; then
    fail "PTY authorization was accepted"
  fi

  printf '%s %s %s\n' \
    'restrict,port-forwarding,command="/bin/sh"' "$public_key" "$marker" \
    > "$authorized_keys"
  if authorization_is_restricted "$authorized_keys" "$marker"; then
    fail "shell authorization was accepted"
  fi

  printf '%s %s %s\n' \
    'restrict,port-forwarding,command="/usr/bin/false",tunnel="0"' "$public_key" "$marker" \
    > "$authorized_keys"
  if authorization_is_restricted "$authorized_keys" "$marker"; then
    fail "additional authorization capability was accepted"
  fi

  printf '%s %s %s\n' \
    'restrict,port-forwarding,command="/usr/bin/false"' "$public_key" "$marker" \
    > "$authorized_keys"
  printf '%s %s\n' "$public_key" "$marker" \
    >> "$authorized_keys"
  if authorization_is_restricted "$authorized_keys" "$marker"; then
    fail "duplicate unsafe authorization was accepted"
  fi

  printf '%s %s %s\n' \
    'restrict,port-forwarding,command="/usr/bin/false"' "$public_key" "$marker" \
    > "$authorized_keys"
  printf '%s %s\n' "$public_key" unrestricted >> "$authorized_keys"
  if authorization_is_restricted "$authorized_keys" "$marker"; then
    fail "the forwarding key was accepted with an unrestricted duplicate"
  fi

  printf '%s\n' \
    'restrict,port-forwarding,command="/usr/bin/false" ssh-ed25519 AAAATEST orbstack-docker-api-work-mini' \
    > "$authorized_keys"
  if authorization_is_restricted "$authorized_keys" "$marker"; then
    fail "malformed forwarding key material was accepted"
  fi

  printf '%s %s %s\n' \
    'restrict,port-forwarding,command="/usr/bin/false"' "$public_key" "$marker" \
    > "$authorized_keys"
  chmod 620 "$authorized_keys"
  if authorization_is_restricted "$authorized_keys" "$marker"; then
    fail "group-writable authorization file was accepted"
  fi

  chmod 600 "$authorized_keys"
  chmod +a "everyone allow read" "$authorized_keys"
  if authorization_is_restricted "$authorized_keys" "$marker"; then
    fail "ACL-readable authorization file was accepted"
  fi
  chmod -N "$authorized_keys"

  chmod 720 "$test_directory"
  if authorization_is_restricted "$authorized_keys" "$marker"; then
    fail "group-writable SSH directory was accepted"
  fi

  chmod 700 "$test_directory"
  printf '%s\n' '# orbstack-docker-api-personal-mini' > "$authorized_keys"
  load_profile personal-mini
  verify_disabled_bridge || fail "commented disabled-profile marker was treated as active"
  printf '%s %s %s\n' \
    'restrict,port-forwarding,command="/usr/bin/false"' "$public_key" \
    orbstack-docker-api-personal-mini > "$authorized_keys"
  if verify_disabled_bridge >/dev/null 2>&1; then
    fail "active authorization was accepted for a disabled profile"
  fi
  printf '%s\n' '# no active bridge' > "$test_directory/elsewhere"
  rm "$authorized_keys"
  ln -s "$test_directory/elsewhere" "$authorized_keys"
  if verify_disabled_bridge >/dev/null 2>&1; then
    fail "unsafe authorization path was accepted for a disabled profile"
  fi

  test_home="$test_directory/home"
  mkdir -p "$test_home/external"
  ln -s "$test_home/external" "$test_home/redirected"
  if HOME="$test_home" path_has_no_symlinked_home_components "$test_home/redirected/state"; then
    fail "symlinked private-state ancestor was accepted"
  fi

  printf 'ok: OrbStack Docker API bridge policy\n'
}

trap cleanup EXIT
main "$@"
