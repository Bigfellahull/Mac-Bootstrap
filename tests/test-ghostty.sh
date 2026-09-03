#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_directory=

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
  local existing_home
  local fragment_link_home
  local new_home
  local personal_home
  local symlink_home

  if [[ "$(uname -s)" != Darwin ]]; then
    printf 'skip: Ghostty configuration tests require macOS\n'
    return
  fi

  test_directory="$(mktemp -d "${TMPDIR:-/tmp}/mac-bootstrap-ghostty-test.XXXXXX")"

  new_home="$test_directory/new-home"
  mkdir -p "$new_home"
  HOME="$new_home" "$ROOT/bootstrap/ghostty.sh" apply air >/dev/null
  grep -Fxq 'config-file = mac-bootstrap.conf' "$new_home/.config/ghostty/config" || \
    fail "new Ghostty config does not load the managed fragment"
  cmp -s "$ROOT/config/ghostty/mac-bootstrap.conf" \
    "$new_home/.config/ghostty/mac-bootstrap.conf" || fail "managed Ghostty config is incorrect"
  HOME="$new_home" "$ROOT/bootstrap/ghostty.sh" verify air || \
    fail "new Ghostty config did not verify"
  HOME="$new_home" "$ROOT/bootstrap/ghostty.sh" apply air >/dev/null
  [[ "$(grep -c '^config-file[[:space:]]*=[[:space:]]*mac-bootstrap\.conf$' \
    "$new_home/.config/ghostty/config")" -eq 1 ]] || fail "Ghostty include was duplicated"

  existing_home="$test_directory/existing-home"
  mkdir -p "$existing_home/.config/ghostty"
  printf '%s\n' \
    'font-family = "Berkeley Mono"' \
    'shell-integration-features = cursor' \
    'shell-integration-features = sudo' \
    'config-file = "mac-bootstrap.conf"' \
    'config-file = user.conf' \
    'config-file = mac-bootstrap.conf' > "$existing_home/.config/ghostty/config"
  printf '%s\n' 'theme = stale' > "$existing_home/.config/ghostty/mac-bootstrap.conf"
  chmod 640 "$existing_home/.config/ghostty/config"
  HOME="$existing_home" "$ROOT/bootstrap/ghostty.sh" apply air >/dev/null
  grep -Fxq 'font-family = "Berkeley Mono"' "$existing_home/.config/ghostty/config" || \
    fail "unrelated Ghostty configuration was not preserved"
  grep -Fxq 'shell-integration-features = cursor' "$existing_home/.config/ghostty/config" || \
    fail "existing Ghostty features were not preserved"
  [[ "$(grep -c '^config-file[[:space:]]*=[[:space:]]*mac-bootstrap\.conf$' \
    "$existing_home/.config/ghostty/config")" -eq 1 ]] || fail "managed include was not normalized"
  [[ "$(grep '^[[:space:]]*config-file[[:space:]]*=' \
    "$existing_home/.config/ghostty/config" | tail -1)" == 'config-file = mac-bootstrap.conf' ]] \
    || fail "managed include is not the final Ghostty include"
  [[ "$(stat -f '%Lp' "$existing_home/.config/ghostty/config")" == 640 ]] || \
    fail "Ghostty config permissions changed"
  cmp -s "$ROOT/config/ghostty/mac-bootstrap.conf" \
    "$existing_home/.config/ghostty/mac-bootstrap.conf" || fail "managed Ghostty config was not updated"

  symlink_home="$test_directory/symlink-home"
  mkdir -p "$symlink_home/.config/ghostty"
  ln -s "$test_directory/elsewhere" "$symlink_home/.config/ghostty/config"
  if HOME="$symlink_home" "$ROOT/bootstrap/ghostty.sh" apply air >/dev/null 2>&1; then
    fail "symlinked Ghostty config was accepted"
  fi

  fragment_link_home="$test_directory/fragment-link-home"
  mkdir -p "$fragment_link_home/.config/ghostty"
  printf '%s\n' 'config-file = mac-bootstrap.conf' > "$fragment_link_home/.config/ghostty/config"
  ln -s "$test_directory/elsewhere" "$fragment_link_home/.config/ghostty/mac-bootstrap.conf"
  if HOME="$fragment_link_home" "$ROOT/bootstrap/ghostty.sh" apply air >/dev/null 2>&1; then
    fail "symlinked managed Ghostty config was accepted"
  fi

  personal_home="$test_directory/personal-home"
  mkdir -p "$personal_home"
  HOME="$personal_home" "$ROOT/bootstrap/ghostty.sh" apply personal-mini
  [[ ! -e "$personal_home/.config/ghostty/config" ]] || \
    fail "Ghostty config was applied to a mini profile"

  printf 'ok: Ghostty Air configuration\n'
}

trap cleanup EXIT
main "$@"
