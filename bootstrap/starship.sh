#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=bootstrap/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

config_source="$MAC_BOOTSTRAP_ROOT/config/starship.toml"
config_target="$HOME/.config/starship.toml"
cache_directories=("$HOME/.cache" "$HOME/.cache/starship")
managed_zsh_sources=("$MAC_BOOTSTRAP_ROOT/config/zsh/common.zsh")
managed_zsh_targets=("$HOME/.config/mac-bootstrap/common.zsh")
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
# shellcheck disable=SC2016
common_line='[[ -r "$HOME/.config/mac-bootstrap/common.zsh" ]] && source "$HOME/.config/mac-bootstrap/common.zsh"'
zsh_lines=("$common_line" "$init_line")

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

validate_cache_targets() {
  local directory

  for directory in "${cache_directories[@]}"; do
    path_has_no_symlinked_home_components "$directory" || return 1
    if [[ -e "$directory" ]]; then
      [[ -d "$directory" && -O "$directory" ]] || return 1
    fi
  done
}

apply_cache_permissions() {
  local directory

  for directory in "${cache_directories[@]}"; do
    if [[ ! -d "$directory" ]]; then
      (umask 022; mkdir "$directory")
    fi
    # Preserve stricter permissions and leave cache contents untouched.
    chmod u+rwx,go-w "$directory"
  done
}

verify_cache_permissions() {
  local directory
  local mode

  validate_cache_targets || return 1
  for directory in "${cache_directories[@]}"; do
    [[ -d "$directory" ]] || return 1
    mode="$(stat -f '%Lp' "$directory")"
    (( (8#$mode & 022) == 0 && (8#$mode & 0700) == 0700 )) || return 1
  done
}

render_zsh_config() {
  local source_file="$1"
  local destination_file="$2"

  if [[ ! -f "$source_file" ]]; then
    printf '%s\n' \
      "$managed_block_start" "${zsh_lines[@]}" "$managed_block_end" \
      > "$destination_file"
    return
  fi

  awk -v block_start="$managed_block_start" -v block_end="$managed_block_end" \
    -v init="$init_line" -v source_line="$source_line" -v common="$common_line" \
    -v profile_kind="$MAC_PROFILE_KIND" '
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
    $0 == init || $0 == source_line || $0 == common { next }
    {
      print
      output_seen = 1
      last_output_blank = ($0 ~ /^[[:space:]]*$/)
    }
    END {
      if (in_managed_block || invalid) exit 2
      if (output_seen && !last_output_blank) print ""
      print block_start
      print common
      print init
      if (profile_kind == "air") print source_line
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
  local index

  validate_cache_targets || die "Cache directories must be owned by the current user and must not be symlinks. Check ~/.cache and ~/.cache/starship."
  validate_regular_target "$config_target"
  for index in "${!managed_zsh_targets[@]}"; do
    validate_regular_target "${managed_zsh_targets[$index]}"
  done
  validate_regular_target "$zsh_config"
  if [[ "$MAC_PROFILE_KIND" == air ]]; then
    validate_regular_target "$image_helper_target"
    path_has_no_symlinked_home_components "$image_helper_target" \
      || die "Refusing a symlinked image helper installation path."
  fi
  prepare_zsh_config "$(dirname "$zsh_config")" \
    || die "Existing zsh configuration is invalid or has an incomplete managed block."

  apply_cache_permissions
  mkdir -p "$(dirname "$config_target")" "$HOME/.config/mac-bootstrap"
  if [[ ! -f "$config_target" ]] || ! cmp -s "$config_source" "$config_target"; then
    install -m 0644 "$config_source" "$config_target"
  fi
  for index in "${!managed_zsh_targets[@]}"; do
    if [[ ! -f "${managed_zsh_targets[$index]}" ]] || \
      ! cmp -s "${managed_zsh_sources[$index]}" "${managed_zsh_targets[$index]}"; then
      install -m 0644 "${managed_zsh_sources[$index]}" "${managed_zsh_targets[$index]}"
    fi
  done

  if [[ "$MAC_PROFILE_KIND" == air ]]; then
    install -m 0755 "$image_helper_source" "$image_helper_target"
  fi

  if [[ -f "$zsh_config" ]] && cmp -s "$zsh_config" "$temporary_zsh_config"; then
    info "Starship and shell enhancements are already configured for zsh"
    return
  fi
  if [[ -f "$zsh_config" ]]; then
    chmod "$(stat -f '%Lp' "$zsh_config")" "$temporary_zsh_config"
  else
    chmod 0644 "$temporary_zsh_config"
  fi
  mv "$temporary_zsh_config" "$zsh_config"
  temporary_zsh_config=

  info "Configured Starship and shell enhancements for zsh"
}

verify_config() {
  local index

  verify_cache_permissions || return 1
  [[ -f "$config_target" && ! -L "$config_target" ]] || return 1
  [[ -f "$zsh_config" && ! -L "$zsh_config" ]] || return 1
  if [[ "$MAC_PROFILE_KIND" == air ]]; then
    [[ -x "$image_helper_target" && ! -L "$image_helper_target" ]] || return 1
    path_has_no_symlinked_home_components "$image_helper_target" || return 1
    cmp -s "$image_helper_source" "$image_helper_target" || return 1
  fi
  cmp -s "$config_source" "$config_target" || return 1
  for index in "${!managed_zsh_targets[@]}"; do
    [[ -f "${managed_zsh_targets[$index]}" && ! -L "${managed_zsh_targets[$index]}" ]] || return 1
    cmp -s "${managed_zsh_sources[$index]}" "${managed_zsh_targets[$index]}" || return 1
  done
  prepare_zsh_config "${TMPDIR:-/tmp}" || return 1
  cmp -s "$zsh_config" "$temporary_zsh_config"
}

main() {
  local command="${1:-}"
  local profile="${2:-}"
  local index

  [[ $# -eq 2 ]] || die "Usage: starship.sh plan|apply|verify PROFILE"
  load_profile "$profile"

  if [[ "$MAC_PROFILE_KIND" == air ]]; then
    managed_zsh_sources+=("$MAC_BOOTSTRAP_ROOT/config/zsh/air.zsh")
    managed_zsh_targets+=("$HOME/.config/mac-bootstrap/air.zsh")
    zsh_lines+=("$source_line")
  else
    managed_block_start='# mac-bootstrap: managed shell integration'
    managed_block_end='# mac-bootstrap: end managed shell integration'
  fi

  case "$command" in
    plan)
      printf '\nManaged Starship and zsh configuration:\n'
      printf '%s: ensure owner access and remove group/other write permissions (non-recursive)\n' "${cache_directories[@]}"
      printf '%s <- %s\n' "$config_target" "$config_source"
      for index in "${!managed_zsh_targets[@]}"; do
        printf '%s <- %s\n' "${managed_zsh_targets[$index]}" "${managed_zsh_sources[$index]}"
        sed 's/^/  /' "${managed_zsh_sources[$index]}"
      done
      if [[ "$MAC_PROFILE_KIND" == air ]]; then
        printf '%s <- %s\n' "$image_helper_target" "$image_helper_source"
      fi
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
