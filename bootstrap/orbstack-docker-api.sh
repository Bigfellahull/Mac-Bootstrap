#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=bootstrap/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

host_socket="$HOME/.orbstack/run/docker.sock"
authorized_keys="$HOME/.ssh/authorized_keys"

path_is_owned_and_not_writable() {
  local path="$1"
  local mode

  [[ "$(stat -f '%u' "$path")" == "$(id -u)" ]] || return 1
  mode="$(stat -f '%Lp' "$path")"
  (( (8#$mode & 022) == 0 )) || return 1
  path_has_no_acl "$path"
}

authorization_file_is_private() {
  local path="$1"
  local ssh_directory

  [[ -f "$path" && ! -L "$path" ]] || return 1
  path_has_no_symlinked_home_components "$path" || return 1
  ssh_directory="$(dirname "$path")"
  [[ -d "$ssh_directory" && ! -L "$ssh_directory" ]] || return 1
  path_is_owned_and_not_writable "$ssh_directory" || return 1
  path_is_owned_and_not_writable "$path"
}

authorization_is_restricted() {
  local path="$1"
  local marker="$2"
  local fingerprint
  local marked_key
  local matching_key_count

  authorization_file_is_private "$path" || return 1

  marked_key="$(awk -v marker="$marker" '
    /^[[:space:]]*(#|$)/ { next }
    $NF == marker {
      marker_count++
      option_count = split(tolower($1), options, ",")
      delete option_seen
      for (option_index = 1; option_index <= option_count; option_index++) {
        option_seen[options[option_index]] = 1
      }
      if (NF == 4 &&
          option_count == 3 &&
          option_seen["restrict"] &&
          option_seen["port-forwarding"] &&
          option_seen["command=\"/usr/bin/false\""]) {
        safe_count++
        print $2, $3, $4
      }
    }
    END { exit !(marker_count == 1 && safe_count == 1) }
  ' "$path")" || return 1

  fingerprint="$(printf '%s\n' "$marked_key" \
    | ssh-keygen -l -E sha256 -f - 2>/dev/null \
    | awk 'NR == 1 { print $2 }')"
  [[ -n "$fingerprint" ]] || return 1
  matching_key_count="$(ssh-keygen -l -E sha256 -f "$path" 2>/dev/null \
    | awk -v fingerprint="$fingerprint" '$2 == fingerprint { count++ } END { print count + 0 }')"
  [[ "$matching_key_count" == 1 ]]
}

authorization_marker_exists() {
  local path="$1"
  local marker="$2"

  [[ -f "$path" && ! -L "$path" ]] || return 1
  awk -v marker="$marker" '
    /^[[:space:]]*(#|$)/ { next }
    $NF == marker { found = 1 }
    END { exit !found }
  ' "$path"
}

foreign_authorization_exists() {
  local marker

  case "$MAC_PROFILE" in
    personal-mini) marker=orbstack-docker-api-work-mini ;;
    work-mini) marker=orbstack-docker-api-personal-mini ;;
    *) return 1 ;;
  esac
  authorization_marker_exists "$authorized_keys" "$marker"
}

host_socket_is_private() {
  [[ -S "$host_socket" && ! -L "$host_socket" ]] || return 1
  path_has_no_symlinked_home_components "$host_socket" || return 1
  path_is_owned_and_not_writable "$host_socket"
}

plan_bridge() {
  local marker="orbstack-docker-api-$MAC_PROFILE"

  printf '\nOrbStack Docker API bridge:\n'
  printf 'state: %s\n' "$MAC_ORBSTACK_API_BRIDGE"
  if [[ "$MAC_ORBSTACK_API_BRIDGE" == enabled ]]; then
    printf 'host socket: %s\n' "$host_socket"
    printf 'SSH authorization marker: %s\n' "$marker"
    printf 'commissioning: docs/orbstack-docker-api.md\n'
  fi
}

verify_bridge() {
  local marker="orbstack-docker-api-$MAC_PROFILE"
  local verification_failed=0

  if ! host_socket_is_private; then
    warn "OrbStack Docker API socket is missing, symlinked, incorrectly owned or writable by another user: $host_socket"
    verification_failed=1
  fi

  if ! authorization_is_restricted "$authorized_keys" "$marker"; then
    warn "Restricted OrbStack Docker API authorization is missing or unsafe: $authorized_keys ($marker)"
    verification_failed=1
  fi
  if foreign_authorization_exists; then
    warn "Authorization for the other mini profile is present: $authorized_keys"
    verification_failed=1
  fi

  return "$verification_failed"
}

verify_disabled_bridge() {
  local marker="orbstack-docker-api-$MAC_PROFILE"

  if [[ ! -e "$authorized_keys" && ! -L "$authorized_keys" ]]; then
    return 0
  fi
  if ! authorization_file_is_private "$authorized_keys"; then
    warn "Could not safely establish that OrbStack Docker API authorization is absent: $authorized_keys"
    return 1
  fi
  if authorization_marker_exists "$authorized_keys" "$marker"; then
    warn "OrbStack Docker API authorization remains active for disabled profile $MAC_PROFILE: $authorized_keys ($marker)"
    return 1
  fi
  if foreign_authorization_exists; then
    warn "Authorization for the other mini profile is present: $authorized_keys"
    return 1
  fi
}

main() {
  local command="${1:-}"
  local profile="${2:-}"

  [[ $# -eq 2 ]] || die "Usage: orbstack-docker-api.sh plan|verify PROFILE"
  load_profile "$profile"

  case "$command" in
    plan)
      if [[ "$MAC_PROFILE_KIND" == mini ]]; then
        plan_bridge
      fi
      ;;
    verify)
      if [[ "$MAC_PROFILE_KIND" == mini ]]; then
        require_macos
        if [[ "$MAC_ORBSTACK_API_BRIDGE" == enabled ]]; then
          verify_bridge
        else
          verify_disabled_bridge
        fi
      fi
      ;;
    *)
      die "Unknown OrbStack Docker API command: $command"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
