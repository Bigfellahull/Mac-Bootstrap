#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=bootstrap/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

print_brewfile() {
  local relative_file="$1"

  printf '\nHomebrew: %s\n' "$relative_file"
  sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' "$MAC_BOOTSTRAP_ROOT/$relative_file"
}

print_tsv() {
  local heading="$1"
  local relative_file="$2"

  [[ -n "$relative_file" ]] || return 0

  printf '\n%s: %s\n' "$heading" "$relative_file"
  sed -e '/^[[:space:]]*$/d' -e '/^[[:space:]]*#/d' "$MAC_BOOTSTRAP_ROOT/$relative_file"
}

main() {
  local profile="$1"
  local brewfile

  load_profile "$profile"

  printf 'mac-bootstrap plan: %s\n' "$MAC_PROFILE"
  printf 'machine kind: %s\n' "$MAC_PROFILE_KIND"

  print_brewfile "config/Brewfile.common"
  for brewfile in "${MAC_PROFILE_BREWFILES[@]}"; do
    print_brewfile "$brewfile"
  done

  print_tsv "Mac App Store" "$MAC_APP_STORE_FILE"
  "$MAC_BOOTSTRAP_ROOT/bootstrap/ghostty.sh" plan "$profile"
  "$MAC_BOOTSTRAP_ROOT/bootstrap/starship.sh" plan "$profile"
  "$MAC_BOOTSTRAP_ROOT/bootstrap/ssh.sh" plan "$profile"
  "$MAC_BOOTSTRAP_ROOT/bootstrap/orbstack-docker-api.sh" plan "$profile"
  "$MAC_BOOTSTRAP_ROOT/bin/local-dev-tls" plan "$profile"

  printf '\nNo applications will be removed. No macOS defaults will be changed.\n'
}

main "$@"
