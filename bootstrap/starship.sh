#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=bootstrap/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

config_source="$MAC_BOOTSTRAP_ROOT/config/starship.toml"
config_target="$HOME/.config/starship.toml"
managed_zsh_source="$MAC_BOOTSTRAP_ROOT/config/zsh/air.zsh"
managed_zsh_target="$HOME/.config/mac-bootstrap/air.zsh"
image_helper_source="$MAC_BOOTSTRAP_ROOT/bin/dev-image"
image_helper_target="$HOME/.config/mac-bootstrap/dev-image"
zsh_config="$HOME/.zshrc"
temporary_zsh_config=
managed_block_start='# mac-bootstrap: managed Air shell integration'
managed_block_end='# mac-bootstrap: end managed Air shell integration'
# Future zsh sessions expand these commands.
# shellcheck disable=SC2016
init_line='eval "$(starship init zsh)"'
# shellcheck disable=SC2016
source_line='[[ -r "$HOME/.config/mac-bootstrap/air.zsh" ]] && source "$HOME/.config/mac-bootstrap/air.zsh"'
zsh_lines=("$init_line" "$source_line")

cleanup() {
  if [[ -n "$temporary_zsh_config" ]]; then
    rm -f "$temporary_zsh_config"
  fi
}

validate_regular_target() {
  local target_file="$1"

  if [[ -L "$target_file" ]]; then
    die "Refusing to replace symlinked shell configuration: $target_file"
  fi

  if [[ -e "$target_file" && ! -f "$target_file" ]]; then
    die "Shell configuration is not a regular file: $target_file"
  fi
}

render_zsh_config() {
  local source_file="$1"
  local destination_file="$2"

  if [[ ! -f "$source_file" ]]; then
    printf '%s\n%s\n%s\n%s\n' \
      "$managed_block_start" "$init_line" "$source_line" "$managed_block_end" \
      > "$destination_file"
    return
  fi

  awk -v block_start="$managed_block_start" -v block_end="$managed_block_end" \
    -v init="$init_line" -v source_line="$source_line" '
    $0 == block_start {
      if (in_managed_block) invalid = 1
      in_managed_block = 1
      next
    }
    $0 == block_end {
      if (!in_managed_block) invalid = 1
      in_managed_block = 0
      next
    }
    in_managed_block { next }
    $0 == init || $0 == source_line { next }
    {
      print
      output_seen = 1
      last_output_blank = ($0 ~ /^[[:space:]]*$/)
    }
    END {
      if (in_managed_block || invalid) exit 2
      if (output_seen && !last_output_blank) print ""
      print block_start
      print init
      print source_line
      print block_end
    }
  ' "$source_file" > "$destination_file"
}

prepare_zsh_config() {
  local temporary_root="$1"

  temporary_zsh_config="$(mktemp "$temporary_root/mac-bootstrap-zsh.XXXXXX")"
  render_zsh_config "$zsh_config" "$temporary_zsh_config" || return 1
  /bin/zsh -n "$temporary_zsh_config"
}

apply_config() {
  validate_regular_target "$config_target"
  validate_regular_target "$managed_zsh_target"
  validate_regular_target "$zsh_config"
  validate_regular_target "$image_helper_target"
  path_has_no_symlinked_home_components "$image_helper_target" \
    || die "Refusing a symlinked image helper installation path."
  prepare_zsh_config "$(dirname "$zsh_config")" \
    || die "Existing zsh configuration is invalid or has an incomplete managed block."

  mkdir -p "$(dirname "$config_target")" "$(dirname "$managed_zsh_target")"
  if [[ ! -f "$config_target" ]] || ! cmp -s "$config_source" "$config_target"; then
    install -m 0644 "$config_source" "$config_target"
  fi
  if [[ ! -f "$managed_zsh_target" ]] || \
    ! cmp -s "$managed_zsh_source" "$managed_zsh_target"; then
    install -m 0644 "$managed_zsh_source" "$managed_zsh_target"
  fi

  install -m 0755 "$image_helper_source" "$image_helper_target"

  if [[ -f "$zsh_config" ]] && cmp -s "$zsh_config" "$temporary_zsh_config"; then
    info "Starship and development VM helpers are already configured for zsh"
    return
  fi
  if [[ -f "$zsh_config" ]]; then
    chmod "$(stat -f '%Lp' "$zsh_config")" "$temporary_zsh_config"
  else
    chmod 0644 "$temporary_zsh_config"
  fi
  mv "$temporary_zsh_config" "$zsh_config"
  temporary_zsh_config=

  info "Configured Starship and development VM helpers for zsh"
}

verify_config() {
  [[ -f "$config_target" && ! -L "$config_target" ]] || return 1
  [[ -f "$managed_zsh_target" && ! -L "$managed_zsh_target" ]] || return 1
  [[ -f "$zsh_config" && ! -L "$zsh_config" ]] || return 1
  [[ -x "$image_helper_target" && ! -L "$image_helper_target" ]] || return 1
  path_has_no_symlinked_home_components "$image_helper_target" || return 1
  cmp -s "$image_helper_source" "$image_helper_target" || return 1
  cmp -s "$config_source" "$config_target" || return 1
  cmp -s "$managed_zsh_source" "$managed_zsh_target" || return 1
  prepare_zsh_config "${TMPDIR:-/tmp}" || return 1
  cmp -s "$zsh_config" "$temporary_zsh_config"
}

main() {
  local command="${1:-}"
  local profile="${2:-}"

  [[ $# -eq 2 ]] || die "Usage: starship.sh plan|apply|verify PROFILE"
  load_profile "$profile"

  [[ "$MAC_PROFILE_KIND" == air ]] || return 0

  case "$command" in
    plan)
      printf '\nManaged Starship and zsh configuration:\n'
      printf '%s <- %s\n' "$config_target" "$config_source"
      printf '%s <- %s\n' "$managed_zsh_target" "$managed_zsh_source"
      printf '%s <- %s\n' "$image_helper_target" "$image_helper_source"
      sed 's/^/  /' "$managed_zsh_source"
      for zsh_line in "${zsh_lines[@]}"; do
        printf '%s: %s\n' "$zsh_config" "$zsh_line"
      done
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
      die "Unknown Starship command: $command"
      ;;
  esac
}

trap cleanup EXIT
main "$@"
