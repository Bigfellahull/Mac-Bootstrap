#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=bootstrap/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

install_brewfile() {
  local relative_file="$1"

  info "Applying $relative_file"
  brew bundle install --no-upgrade --verbose --file "$MAC_BOOTSTRAP_ROOT/$relative_file"
}

main() {
  local profile="$1"
  local brewfile

  require_macos
  load_profile "$profile"
  activate_homebrew

  "$MAC_BOOTSTRAP_ROOT/bootstrap/google-drive.sh" apply "$profile"
  install_brewfile "config/Brewfile.common"
  for brewfile in "${MAC_PROFILE_BREWFILES[@]}"; do
    install_brewfile "$brewfile"
  done
  "$MAC_BOOTSTRAP_ROOT/bootstrap/google-drive.sh" apply "$profile"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
