#!/usr/bin/env bash

set -Eeuo pipefail

MAC_BOOTSTRAP_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly -a MAC_BOOTSTRAP_PROFILES=(air personal-mini work-mini)

info() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "This command must run on macOS."
}

list_profiles() {
  printf '%s\n' "${MAC_BOOTSTRAP_PROFILES[@]}"
}

profile_is_known() {
  local known_profile

  for known_profile in "${MAC_BOOTSTRAP_PROFILES[@]}"; do
    [[ "$1" == "$known_profile" ]] && return 0
  done
  return 1
}

path_has_no_acl() {
  [[ "$(/bin/ls -lde "$1" 2>/dev/null | wc -l | tr -d '[:space:]')" == 1 ]]
}

path_has_no_symlinked_home_components() {
  local component
  local inspected_path="$HOME"
  local relative_path

  [[ "$1" == "$HOME" || "$1" == "$HOME/"* ]] || return 1
  relative_path="${1#"$HOME"}"
  relative_path="${relative_path#/}"

  while [[ -n "$relative_path" ]]; do
    component="${relative_path%%/*}"
    [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
    inspected_path="$inspected_path/$component"
    [[ ! -L "$inspected_path" ]] || return 1
    if [[ "$relative_path" == */* ]]; then
      relative_path="${relative_path#*/}"
    else
      relative_path=
    fi
  done
}

load_profile() {
  local profile="$1"
  local profile_file="$MAC_BOOTSTRAP_ROOT/profiles/$profile.env"

  profile_is_known "$profile" || die "Unknown profile: $profile"
  [[ -f "$profile_file" ]] || die "Unknown profile: $profile"

  # ShellCheck cannot see globals consumed by scripts sourcing this library.
  # shellcheck disable=SC2034
  MAC_PROFILE="$profile"
  MAC_PROFILE_KIND=
  # shellcheck disable=SC2034
  MAC_PROFILE_BREWFILES=()
  # shellcheck disable=SC2034
  MAC_APP_STORE_FILE=
  MAC_ORBSTACK_API_BRIDGE=
  MAC_LOCAL_DEV_TLS=

  # shellcheck source=/dev/null
  source "$profile_file"

  case "$profile:$MAC_PROFILE_KIND" in
    air:air|personal-mini:mini|work-mini:mini) ;;
    *) die "Profile $profile does not define its expected MAC_PROFILE_KIND." ;;
  esac
  # A local data flag opts each mini in without editing shared profiles.
  local bridge_flag="$HOME/.config/mac-bootstrap/docker-api-bridge.$profile"
  if [[ "$MAC_PROFILE_KIND" == mini && ( -e "$bridge_flag" || -L "$bridge_flag" ) ]]; then
    path_has_no_symlinked_home_components "$bridge_flag" \
      && [[ -f "$bridge_flag" && -O "$bridge_flag" ]] \
      || die "Unsafe Docker API opt-in file: $bridge_flag"
    local bridge_mode
    if [[ "$(uname -s)" == Darwin ]]; then
      bridge_mode="$(stat -f '%Lp' "$bridge_flag")"
    else
      bridge_mode="$(stat -c '%a' "$bridge_flag")"
    fi
    [[ "$bridge_mode" == 600 ]] || die "Docker API opt-in file must have mode 600: $bridge_flag"
    MAC_ORBSTACK_API_BRIDGE="$(cat "$bridge_flag")"
  fi
  case "$MAC_ORBSTACK_API_BRIDGE" in
    enabled|disabled) ;;
    *) die "Profile $profile does not define a valid MAC_ORBSTACK_API_BRIDGE state." ;;
  esac
  if [[ "$MAC_PROFILE_KIND" != mini && "$MAC_ORBSTACK_API_BRIDGE" != disabled ]]; then
    die "Profile $profile enables the OrbStack API bridge on a non-mini machine."
  fi
  case "$MAC_LOCAL_DEV_TLS" in
    enabled|disabled) ;;
    *) die "Profile $profile does not define a valid MAC_LOCAL_DEV_TLS state." ;;
  esac
  if [[ "$MAC_PROFILE_KIND" != mini && "$MAC_LOCAL_DEV_TLS" != disabled ]]; then
    die "Profile $profile enables local development TLS on a non-mini machine."
  fi
}

homebrew_binary() {
  if [[ -x /opt/homebrew/bin/brew ]]; then
    printf '%s\n' /opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew ]]; then
    printf '%s\n' /usr/local/bin/brew
  else
    return 1
  fi
}

activate_homebrew() {
  local brew_bin

  brew_bin="$(homebrew_binary)" || die "Homebrew is not installed."
  eval "$("$brew_bin" shellenv)"
}
