#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=bootstrap/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

google_support_directory="$HOME/Library/Application Support/Google"

# Validate the user-owned path before repairing the Google directory itself.
google_drive_validate_path() {
  local directory
  local owner
  local mode
  local user_id

  user_id="$(id -u)"
  [[ "$user_id" != 0 ]] || die "Run Google Drive setup as the normal macOS user, not root."
  if [[ -L "$HOME" ]] || ! path_has_no_symlinked_home_components "$google_support_directory"; then
    die "Google Drive support path contains a symlink."
  fi

  directory="$google_support_directory"
  while :; do
    if [[ -e "$directory" ]]; then
      [[ -d "$directory" ]] || die "Expected a directory: $directory"
      owner="$(stat -f '%u' "$directory")"
      if [[ "$owner" != "$user_id" ]]; then
        [[ "$directory" == "$google_support_directory" && "$owner" == 0 ]] \
          || die "Unexpected ownership on Google Drive support path: $directory"
      fi
      mode="$(stat -f '%Lp' "$directory")"
      (( (8#$mode & 0022) == 0 )) \
        || die "Google Drive support path is writable by another user: $directory"
    fi
    [[ "$directory" != "$HOME" ]] || break
    directory="$(dirname "$directory")"
  done

  if [[ -e "$google_support_directory" ]]; then
    path_has_no_acl "$google_support_directory" \
      || die "Google Drive support directory has an ACL requiring manual review: $google_support_directory"
  fi
}

# Check ownership and access without creating directories or requesting sudo.
google_drive_verify() {
  google_drive_validate_path
  [[ -d "$google_support_directory" ]] \
    || die "Google Drive support directory is missing; run bootstrap/google-drive.sh apply air."
  [[ "$(stat -f '%u' "$google_support_directory")" == "$(id -u)" ]] \
    || die "Google Drive support directory is owned by root; run bootstrap/google-drive.sh apply air."
  [[ -r "$google_support_directory" && -w "$google_support_directory" && -x "$google_support_directory" ]] \
    || die "Google Drive support directory is not accessible to this user: $google_support_directory"
}

# Prepare Google's parent directory without changing existing application data.
google_drive_apply() {
  google_drive_validate_path
  if [[ ! -d "$google_support_directory" ]]; then
    (umask 077; mkdir -p "$google_support_directory") \
      || die "Could not create Google Drive support directory: $google_support_directory"
    info "Created Google Drive support directory for the current user"
  elif [[ "$(stat -f '%u' "$google_support_directory")" == 0 ]]; then
    info "Repairing Google Drive support directory ownership; administrator approval may be required"
    sudo /usr/sbin/chown -h "$(id -u):$(id -g)" "$google_support_directory" \
      || die "Could not repair Google Drive support directory ownership."
  fi
  google_drive_verify
}

# Dispatch Air-only preparation and read-only verification.
google_drive_main() {
  local command="${1:-}"

  [[ $# -eq 2 ]] || die "Usage: google-drive.sh plan|apply|verify PROFILE"
  case "$command" in plan|apply|verify) ;; *) die "Unknown Google Drive command: $command" ;; esac
  load_profile "$2"
  [[ "$MAC_PROFILE_KIND" == air ]] || return 0
  if [[ "$command" == plan ]]; then
    printf '\nGoogle Drive: prepare %s for the current user.\n' "$google_support_directory"
    return 0
  fi
  require_macos
  case "$command" in
    apply) google_drive_apply ;;
    verify) google_drive_verify ;;
  esac
  info "Google Drive support directory is owned by and accessible to the current user"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  google_drive_main "$@"
fi
