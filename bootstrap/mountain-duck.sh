#!/usr/bin/env bash
set -Eeuo pipefail

# shellcheck source=bootstrap/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

bookmarks="$HOME/Library/Group Containers/G69SCX94XU.duck/Library/Application Support/duck/Bookmarks"
settings="$HOME/.config/mac-bootstrap/ssh-air.tsv"
scratch=
cleanup() { [[ -z "$scratch" ]] || rm -rf "$scratch"; }
trap cleanup EXIT

# Validate every existing component without changing the shared app directory.
validate_destination() {
  local target="$bookmarks" mode
  path_has_no_symlinked_home_components "$target" || die "Symlinked bookmark directory: $target"
  while [[ "$target" != "$HOME" ]]; do
    if [[ -e "$target" ]]; then
      [[ -d "$target" && "$(stat -f '%u' "$target")" == "$(id -u)" ]] || die "Unsafe bookmark directory: $target"
      mode="$(stat -f '%Lp' "$target")"
      (( (8#$mode & 0022) == 0 )) || die "Bookmark directory is writable by another user: $target"
    fi
    target="$(dirname "$target")"
  done
}

# Manage connection fields only; preserve app-specific preferences and other keys.
field() {
  local key="$1" value="$2" current
  current="$(/usr/bin/plutil -extract "$key" raw -o - "$prepared" 2>/dev/null || true)"
  [[ "$current" == "$value" ]] || /usr/bin/plutil -replace "$key" -string "$value" "$prepared"
}

ensure_app_stopped() {
  local app="$1" status=0
  pgrep -x "$app" >/dev/null || status=$?
  [[ "$status" != 0 ]] || die "Quit Mountain Duck and Cyberduck before updating shared bookmarks, then rerun."
  [[ "$status" == 1 ]] || die "Cannot inspect running apps; rerun outside a restricted sandbox."
}

main() {
  local action="${1:-}" role uuid target prepared user changed=0
  [[ $# -eq 2 ]] || die "Usage: mountain-duck.sh plan|apply|verify PROFILE"
  case "$action" in plan|apply|verify) ;; *) die "Unknown Mountain Duck action: $action" ;; esac
  load_profile "$2"
  [[ "$MAC_PROFILE_KIND" == air ]] || return 0
  if [[ "$action" == plan ]]; then
    printf '\nMountain Duck: Finder access to work-dev and personal-dev using existing SSH routes.\n'
    printf 'Managed SFTP bookmarks; see docs/mountain-duck.md for first connection and licence.\n'
    return
  fi
  require_macos
  if [[ ! -e "$settings" && ! -L "$settings" ]]; then
    warn "Configure Air SSH first; see docs/remote-access.md."
    [[ "$action" == apply ]] && return 0
    return 1
  fi
  "$MAC_BOOTSTRAP_ROOT/bootstrap/ssh.sh" verify air >/dev/null
  validate_destination
  scratch="$(mktemp -d "${TMPDIR:-/tmp}/mac-bootstrap-duck.XXXXXX")"
  for role in work personal; do
    case "$role" in
      work) uuid=EB02D0D1-44D3-4C22-86FB-28BDFD051A41 ;;
      personal) uuid=D782E44A-3D37-41CA-8269-F5A901F56BF0 ;;
    esac
    target="$bookmarks/$uuid.duck"
    prepared="$scratch/$uuid.duck"
    [[ ! -L "$target" ]] || die "Symlinked bookmark: $target"
    if [[ -e "$target" ]]; then
      [[ -f "$target" && "$(stat -f '%u' "$target")" == "$(id -u)" ]] || die "Unsafe bookmark: $target"
      /usr/bin/plutil -lint "$target" >/dev/null || die "Invalid bookmark: $target"
      cp "$target" "$prepared"
    else
      printf '<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict/></plist>\n' > "$prepared"
    fi
    user="$(awk -F '\t' -v role="$role" '$1 == role {print $4}' "$settings")"
    field UUID "$uuid"
    field Protocol sftp
    field Nickname "$role-dev"
    field Hostname "$role-dev"
    field Port 32222
    field Username "$user@$role-dev"
    field Path "/home/$user"
    # The bookmark format stores a literal home-relative key path.
    # shellcheck disable=SC2088
    field 'Private Key File' "~/.ssh/$role-mini_ed25519"
    if ! cmp -s "$prepared" "$target"; then changed=1; fi
  done
  if [[ "$action" == verify ]]; then
    [[ "$changed" == 0 ]] || die "Mountain Duck bookmarks are missing or differ; run bootstrap/mountain-duck.sh apply air."
    info "Mountain Duck bookmark configuration verified offline; test Finder connections separately."
    return
  fi
  if [[ "$changed" == 1 ]]; then
    ensure_app_stopped 'Mountain Duck'
    ensure_app_stopped Cyberduck
    (umask 077; mkdir -p "$bookmarks")
    for prepared in "$scratch"/*.duck; do
      target="$bookmarks/$(basename "$prepared")"
      if ! cmp -s "$prepared" "$target"; then
        local staged
        staged="$(mktemp "$bookmarks/.mac-bootstrap-duck.XXXXXX")"
        if ! install -m 600 "$prepared" "$staged" || ! mv "$staged" "$target"; then
          rm -f "$staged"
          die "Could not install bookmark: $target"
        fi
      fi
    done
  fi
  info "Mountain Duck bookmarks configured. Open the app and follow docs/mountain-duck.md."
}
main "$@"
