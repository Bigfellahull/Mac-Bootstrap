#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=bootstrap/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ghostty_config="$HOME/.config/ghostty/config"
managed_config="$HOME/.config/ghostty/mac-bootstrap.conf"
managed_source="$MAC_BOOTSTRAP_ROOT/config/ghostty/mac-bootstrap.conf"
include_setting='config-file = mac-bootstrap.conf'
temporary_config=

cleanup() {
  if [[ -n "$temporary_config" ]]; then
    rm -f "$temporary_config"
  fi
}

validate_regular_target() {
  local target_file="$1"

  if [[ -L "$target_file" ]]; then
    die "Refusing to replace symlinked Ghostty configuration: $target_file"
  fi

  if [[ -e "$target_file" && ! -f "$target_file" ]]; then
    die "Ghostty configuration is not a regular file: $target_file"
  fi
}

render_config() {
  local source_file="$1"
  local destination_file="$2"

  if [[ ! -f "$source_file" ]]; then
    printf '%s\n' "$include_setting" > "$destination_file"
    return
  fi

  awk -v required="$include_setting" '
    /^[[:space:]]*config-file[[:space:]]*=/ {
      value = $0
      sub(/^[^=]*=[[:space:]]*/, "", value)
      sub(/[[:space:]]*#.*/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (value == "mac-bootstrap.conf" || value == "\"mac-bootstrap.conf\"") {
        next
      }
    }
    {
      print
      output_seen = 1
      last_output_blank = ($0 ~ /^[[:space:]]*$/)
    }
    END {
      if (output_seen && !last_output_blank) print ""
      print required
    }
  ' "$source_file" > "$destination_file"
}

prepare_config() {
  temporary_config="$(mktemp "${TMPDIR:-/tmp}/mac-bootstrap-ghostty.XXXXXX")"
  render_config "$ghostty_config" "$temporary_config"
}

install_managed_config() {
  mkdir -p "$(dirname "$managed_config")"
  if [[ -f "$managed_config" ]] && cmp -s "$managed_source" "$managed_config"; then
    return
  fi
  install -m 0644 "$managed_source" "$managed_config"
}

apply_config() {
  validate_regular_target "$ghostty_config"
  validate_regular_target "$managed_config"
  prepare_config
  install_managed_config

  if [[ -f "$ghostty_config" ]] && cmp -s "$ghostty_config" "$temporary_config"; then
    info "Ghostty preferences are already configured"
    return
  fi

  if [[ -f "$ghostty_config" ]]; then
    chmod "$(stat -f '%Lp' "$ghostty_config")" "$temporary_config"
  fi
  mv "$temporary_config" "$ghostty_config"
  temporary_config=
  info "Configured Ghostty preferences in $managed_config"
}

verify_config() {
  [[ -f "$ghostty_config" && ! -L "$ghostty_config" ]] || return 1
  [[ -f "$managed_config" && ! -L "$managed_config" ]] || return 1
  cmp -s "$managed_source" "$managed_config" || return 1

  prepare_config
  cmp -s "$ghostty_config" "$temporary_config"
}

main() {
  local command="${1:-}"
  local profile="${2:-}"

  [[ $# -eq 2 ]] || die "Usage: ghostty.sh plan|apply|verify PROFILE"
  load_profile "$profile"

  [[ "$MAC_PROFILE_KIND" == air ]] || return 0

  case "$command" in
    plan)
      printf '\nManaged Ghostty configuration:\n'
      printf '%s: %s\n' "$ghostty_config" "$include_setting"
      printf '%s:\n' "$managed_config"
      sed 's/^/  /' "$managed_source"
      ;;
    apply)
      require_macos
      apply_config
      ;;
    verify)
      require_macos
      verify_config
      ;;
    *)
      die "Unknown Ghostty command: $command"
      ;;
  esac
}

trap cleanup EXIT
main "$@"
