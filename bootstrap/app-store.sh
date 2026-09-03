#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=bootstrap/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

main() {
  local profile="$1"
  local app_id
  local app_name
  local failed=0
  local installed_ids

  require_macos
  load_profile "$profile"

  if [[ -z "$MAC_APP_STORE_FILE" ]]; then
    info "No Mac App Store applications are defined for $MAC_PROFILE"
    return 0
  fi

  command -v mas >/dev/null 2>&1 || die "mas is not installed. Apply the Homebrew manifests first."
  installed_ids="$(mas list | awk '{print $1}')"

  while IFS=$'\t' read -r app_id app_name; do
    [[ -n "$app_id" && "$app_id" != \#* ]] || continue

    if grep -qx "$app_id" <<<"$installed_ids"; then
      info "$app_name is already installed"
      continue
    fi

    info "Installing $app_name from the Mac App Store"
    if ! mas install "$app_id"; then
      warn "Could not install $app_name ($app_id). Check that the Mac App Store is signed in."
      failed=1
    fi
  done < "$MAC_BOOTSTRAP_ROOT/$MAC_APP_STORE_FILE"

  return "$failed"
}

main "$@"
