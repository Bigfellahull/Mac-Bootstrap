#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=bootstrap/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

verification_failed=0

pass() {
  printf 'ok: %s\n' "$*"
}

fail() {
  printf 'missing: %s\n' "$*" >&2
  verification_failed=1
}

verify_brewfile() {
  local relative_file="$1"

  if HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --no-upgrade \
    --file="$MAC_BOOTSTRAP_ROOT/$relative_file" >/dev/null; then
    pass "$relative_file"
  else
    fail "$relative_file"
  fi
}

verify_app_store() {
  local app_id
  local app_name
  local installed_ids

  [[ -n "$MAC_APP_STORE_FILE" ]] || return 0

  if ! command -v mas >/dev/null 2>&1; then
    fail "mas, required to verify Mac App Store applications"
    return 0
  fi

  if ! installed_ids="$(mas list | awk '{print $1}')"; then
    fail "Mac App Store applications; mas could not list installed applications"
    return 0
  fi
  while IFS=$'\t' read -r app_id app_name; do
    [[ -n "$app_id" && "$app_id" != \#* ]] || continue

    if grep -qx "$app_id" <<<"$installed_ids"; then
      pass "$app_name"
    else
      fail "$app_name ($app_id)"
    fi
  done < "$MAC_BOOTSTRAP_ROOT/$MAC_APP_STORE_FILE"
}

verify_remote_login() {
  local remote_login

  [[ "$MAC_PROFILE_KIND" == "mini" ]] || return 0

  if remote_login="$(sudo -n /usr/sbin/systemsetup -getremotelogin 2>/dev/null)"; then
    if [[ "$remote_login" == *On ]]; then
      pass "Remote Login"
    else
      fail "Remote Login"
    fi
  else
    warn "Could not verify Remote Login without administrator access; check it during commissioning."
  fi
}

application_is_installed() {
  [[ -d "/Applications/$1" || -d "$HOME/Applications/$1" ]]
}

warn_about_excluded_software() {
  if application_is_installed Docker.app; then
    warn "Docker Desktop is installed; the mini architecture uses OrbStack instead."
  fi

  if command -v colima >/dev/null 2>&1; then
    warn "Colima is installed; the mini architecture uses OrbStack instead."
  fi

  if application_is_installed "Podman Desktop.app" || command -v podman >/dev/null 2>&1; then
    warn "Podman is installed; the mini architecture uses OrbStack instead."
  fi

  if [[ "$MAC_PROFILE_KIND" == air ]] && application_is_installed OrbStack.app; then
    warn "OrbStack is installed; it belongs only on the mini profiles."
  fi

  if application_is_installed Xcode.app; then
    warn "Full Xcode is installed; this bootstrap requires only the Command Line Tools."
  fi
}

main() {
  local profile="$1"
  local option="${2:-}"
  local brewfile

  require_macos
  load_profile "$profile"

  [[ -z "$option" || "$option" == "--skip-app-store" ]] || die "Unknown option: $option"

  printf 'mac-bootstrap verification: %s\n' "$MAC_PROFILE"
  printf '=======================================\n'

  if xcode-select -p >/dev/null 2>&1; then
    pass "Xcode Command Line Tools"
  else
    fail "Xcode Command Line Tools"
  fi

  if homebrew_binary >/dev/null 2>&1; then
    activate_homebrew
    verify_brewfile "config/Brewfile.common"
    for brewfile in "${MAC_PROFILE_BREWFILES[@]}"; do
      verify_brewfile "$brewfile"
    done
  else
    fail "Homebrew"
  fi

  if [[ "$option" != "--skip-app-store" ]]; then
    verify_app_store
  fi
  if [[ "$MAC_PROFILE_KIND" == air ]]; then
    if "$MAC_BOOTSTRAP_ROOT/bootstrap/google-drive.sh" verify "$profile"; then
      pass "Google Drive support directory"
    else
      fail "Google Drive support directory"
    fi
    if "$MAC_BOOTSTRAP_ROOT/bootstrap/ssh.sh" verify "$profile"; then
      pass "Air SSH routing configuration"
    else
      fail "Air SSH routing configuration"
    fi
    if "$MAC_BOOTSTRAP_ROOT/bootstrap/mountain-duck.sh" verify "$profile"; then
      pass "Mountain Duck bookmarks"
    else
      fail "Mountain Duck bookmarks"
    fi
    if "$MAC_BOOTSTRAP_ROOT/bootstrap/ghostty.sh" verify "$profile"; then
      pass "Ghostty preferences and SSH integration"
    else
      fail "Ghostty preferences and SSH integration"
    fi
  fi
  if "$MAC_BOOTSTRAP_ROOT/bootstrap/starship.sh" verify "$profile"; then
    pass "Starship zsh configuration"
  else
    fail "Starship zsh configuration"
  fi
  if [[ "$MAC_PROFILE_KIND" == mini ]]; then
    if "$MAC_BOOTSTRAP_ROOT/bootstrap/orbstack-docker-api.sh" verify "$profile"; then
      pass "OrbStack Docker API bridge policy"
    else
      fail "OrbStack Docker API bridge policy"
    fi
  fi
  if [[ "$MAC_LOCAL_DEV_TLS" == enabled ]]; then
    if "$MAC_BOOTSTRAP_ROOT/bin/local-dev-tls" verify "$profile"; then
      pass "Local development TLS CA, trust and leaf material"
    else
      fail "Local development TLS CA, trust and leaf material"
    fi
  fi
  verify_remote_login
  warn_about_excluded_software

  return "$verification_failed"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
