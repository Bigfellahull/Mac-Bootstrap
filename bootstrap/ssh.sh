#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=bootstrap/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

settings="$HOME/.config/mac-bootstrap/ssh-air.tsv"
ssh_config="$HOME/.ssh/config"
managed_config="$HOME/.ssh/mac-bootstrap/air.conf"
block_start='# mac-bootstrap: managed Air SSH routing'
block_end='# mac-bootstrap: end managed Air SSH routing'
temporary_directory=

# Remove only scratch files created by this invocation.
cleanup() {
  [[ -z "$temporary_directory" ]] || rm -rf "$temporary_directory"
}

# Reject paths that could redirect writes or accept another user's settings.
validate_path() {
  local target="$1"
  local mode

  path_has_no_symlinked_home_components "$target" || die "Symlinked SSH path: $target"
  if [[ -e "$target" ]]; then
    [[ -f "$target" || -d "$target" ]] || die "Unsupported SSH path: $target"
    [[ "$(stat -f '%u' "$target")" == "$(id -u)" ]] || die "SSH path is not owned by this user: $target"
    mode="$(stat -f '%Lp' "$target")"
    (( (8#$mode & 0022) == 0 )) || die "SSH path is writable by another user: $target"
    path_has_no_acl "$target" || die "SSH path has an ACL requiring manual review: $target"
  fi
}

# Render two explicit destinations without evaluating local settings as code.
render_routes() {
  awk -F '\t' '
    function reject() { invalid = 1; exit 1 }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      if (NF != 4 || ($1 != "work" && $1 != "personal") || seen[$1]++) reject()
      if ($2 !~ /^[a-z0-9][a-z0-9-]*\.[a-z0-9][a-z0-9-]*\.ts\.net$/) reject()
      if ($3 !~ /^[a-z_][a-z0-9_-]*$/ || $4 !~ /^[a-z_][a-z0-9_-]*$/) reject()
      if (hosts[$2]++) reject()
      host[$1] = $2; mac[$1] = $3; linux[$1] = $4
    }
    END {
      if (invalid || !seen["work"] || !seen["personal"]) exit 1
      split("work personal", profiles, " ")
      for (i = 1; i <= 2; i++) {
        p = profiles[i]
        printf "Host %s-mini\n  HostName %s\n  Port 22\n  User %s\n  ProxyCommand none\n", p, host[p], mac[p]
        printf "  IdentityFile ~/.ssh/%s-mini_ed25519\n", p
        printf "\nHost %s-dev\n  HostName 127.0.0.1\n  Port 32222\n  User %s@%s-dev\n", p, linux[p], p
        printf "  ProxyJump %s-mini\n  IdentityFile ~/.ssh/%s-mini_ed25519\n", p, p
        printf "  HostKeyAlias %s-dev-via-%s-mini\n\n", p, p
      }
      print "Host work-mini work-dev personal-mini personal-dev"
      print "  IdentitiesOnly yes\n  ForwardAgent no\n  ControlMaster no\n  ControlPath none"
      print "  ServerAliveInterval 30\n  ServerAliveCountMax 3"
      print "\nHost *"
    }
  ' "$settings"
}

# Prepend a global include while preserving all configuration outside our block.
render_main_config() {
  local input=/dev/null
  [[ ! -f "$ssh_config" ]] || input="$ssh_config"
  awk -v start="$block_start" -v end="$block_end" '
    BEGIN {
      print start
      print "Include ~/.ssh/mac-bootstrap/air.conf"
      print "Host *"
      print end
    }
    $0 == start { if (inside || seen++) invalid = 1; inside = 1; next }
    $0 == end { if (!inside) invalid = 1; inside = 0; next }
    !inside { print }
    END { if (inside || invalid) exit 1 }
  ' "$input"
}

# Validate only the generated fragment, so user Match exec directives never run.
prepare_config() {
  local target
  local alias

  for target in "$HOME/.ssh" "$HOME/.ssh/mac-bootstrap" "$ssh_config" "$managed_config" \
    "$HOME/.config" "$HOME/.config/mac-bootstrap" "$settings"; do
    validate_path "$target"
  done
  for target in "$settings" "$ssh_config" "$managed_config"; do
    [[ ! -e "$target" || -f "$target" ]] || die "Expected a regular file: $target"
  done
  temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/mac-bootstrap-ssh.XXXXXX")"
  render_routes > "$temporary_directory/air.conf" \
    || die "Invalid SSH settings; supply distinct Tailscale DNS names and usernames for work and personal in $settings"
  render_main_config > "$temporary_directory/config" \
    || die "Existing SSH configuration has an incomplete or duplicate managed block."
  for alias in work-mini work-dev personal-mini personal-dev; do
    /usr/bin/ssh -G -F "$temporary_directory/air.conf" "$alias" >/dev/null 2>&1 \
      || die "Generated SSH configuration is invalid for $alias"
  done
}

# Install prepared files atomically within each destination directory.
install_config() {
  local source_file="$1"
  local target="$2"
  local mode="$3"
  local staged

  if [[ -f "$target" ]] && cmp -s "$source_file" "$target"; then
    return
  fi
  staged="$(mktemp "$(dirname "$target")/.mac-bootstrap-ssh.XXXXXX")"
  if ! install -m "$mode" "$source_file" "$staged" || ! mv "$staged" "$target"; then
    rm -f "$staged"
    die "Could not install SSH configuration: $target"
  fi
}

# Dispatch Air-only installation and offline configuration verification.
main() {
  local command="${1:-}"
  local mode=600

  [[ $# -eq 2 ]] || die "Usage: ssh.sh plan|apply|verify PROFILE"
  case "$command" in plan|apply|verify) ;; *) die "Unknown SSH command: $command" ;; esac
  load_profile "$2"
  [[ "$MAC_PROFILE_KIND" == air ]] || return 0
  if [[ "$command" == plan ]]; then
    printf '\nManaged Air SSH routing:\n'
    printf 'work-dev -> work-mini; personal-dev -> personal-mini, using Tailscale everywhere\n'
    printf 'Local settings: %s\nManaged fragment: %s\n' "$settings" "$managed_config"
    printf 'Commissioning: docs/remote-access.md; keys and host trust remain manual.\n'
    return
  fi
  require_macos
  if [[ ! -e "$settings" && ! -L "$settings" ]]; then
    warn "Air SSH settings are missing: $settings; follow docs/remote-access.md."
    [[ "$command" == apply ]] && return 0
    return 1
  fi
  prepare_config
  if [[ "$command" == verify ]]; then
    if ! cmp -s "$temporary_directory/air.conf" "$managed_config" \
      || ! cmp -s "$temporary_directory/config" "$ssh_config"; then
      die "Air SSH configuration is missing or differs; run bootstrap/ssh.sh apply air."
    fi
    info "Managed Air SSH routes verified offline; authentication and connectivity require commissioning."
    return
  fi
  [[ ! -f "$ssh_config" ]] || mode="$(stat -f '%Lp' "$ssh_config")"
  (umask 077; mkdir -p "$HOME/.ssh/mac-bootstrap")
  install_config "$temporary_directory/air.conf" "$managed_config" 600
  install_config "$temporary_directory/config" "$ssh_config" "$mode"
  info "Configured Air SSH routing; complete authentication and connection checks in docs/remote-access.md."
}

trap cleanup EXIT
main "$@"
