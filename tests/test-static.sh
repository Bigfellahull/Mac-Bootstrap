#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  printf 'not ok: %s\n' "$*" >&2
  exit 1
}

main() {
  local shell_files=()

  while IFS= read -r shell_file; do
    shell_files+=("$shell_file")
    bash -n "$shell_file"
  done < <(find "$ROOT/bin" "$ROOT/bootstrap" "$ROOT/tests" -type f | sort)

  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "${shell_files[@]}"
  else
    printf 'skip: shellcheck is not installed\n'
  fi

  rg -qx 'cask "orbstack"' "$ROOT/config/Brewfile.mini" || fail "OrbStack mini manifest is missing"
  rg -qx 'brew "mkcert"' "$ROOT/config/Brewfile.mini" || fail "mkcert mini manifest is missing"
  rg -qx 'cask "parallels"' "$ROOT/config/Brewfile.work-mini" || fail "Parallels work manifest is missing"
  rg -qx 'cask "datagrip"' "$ROOT/config/Brewfile.air" || fail "DataGrip Air manifest is missing"
  rg -qx 'cask "cleanshot"' "$ROOT/config/Brewfile.air" || fail "CleanShot X Air manifest is missing"
  rg -qx 'cask "microsoft-teams"' "$ROOT/config/Brewfile.air" || fail "Microsoft Teams Air manifest is missing"
  rg -qx 'brew "starship"' "$ROOT/config/Brewfile.air" || fail "Starship Air formula is missing"
  for shell_formula in bat fd fzf ripgrep zoxide zsh-autosuggestions zsh-syntax-highlighting; do
    rg -qx "brew \"$shell_formula\"" "$ROOT/config/Brewfile.air" \
      || fail "$shell_formula Air formula is missing"
  done
  rg -q $'^1612653346\tFieldKit$' "$ROOT/config/app-store.air.tsv" || fail "FieldKit App Store entry is missing"
  rg -Fq 'shell-integration-features = ssh-env,ssh-terminfo' \
    "$ROOT/config/ghostty/mac-bootstrap.conf" || fail "Ghostty SSH integration is missing"
  rg -Fq 'theme = dark:Catppuccin Frappe,light:Catppuccin Latte' \
    "$ROOT/config/ghostty/mac-bootstrap.conf" || fail "Ghostty theme is missing"
  rg -Fq 'eval "$(starship init zsh)"' \
    "$ROOT/bootstrap/starship.sh" || fail "Starship zsh initialization is missing"
  rg -Fq 'config/zsh/air.zsh' \
    "$ROOT/bootstrap/starship.sh" || fail "Air zsh configuration is not installed"
  rg -Fq 'source <(fzf --zsh)' \
    "$ROOT/config/zsh/air.zsh" || fail "fzf zsh integration is missing"
  rg -Fq 'eval "$(zoxide init zsh)"' \
    "$ROOT/config/zsh/air.zsh" || fail "zoxide zsh integration is missing"
  rg -Fq 'zsh-autosuggestions.zsh' \
    "$ROOT/config/zsh/air.zsh" || fail "zsh autosuggestions are not loaded"
  rg -Fq 'zsh-syntax-highlighting.zsh' \
    "$ROOT/config/zsh/air.zsh" || fail "zsh syntax highlighting is not loaded"
  rg -Fqx 'work-dev() {' \
    "$ROOT/config/zsh/air.zsh" || fail "work development VM function is missing"
  rg -Fqx '  ssh -t work-dev@orb "tmux new -As ${(q)session}"' \
    "$ROOT/config/zsh/air.zsh" || fail "work development VM function is incorrect"
  rg -Fqx 'personal-dev() {' \
    "$ROOT/config/zsh/air.zsh" || fail "personal development VM function is missing"
  rg -Fqx '  ssh -t personal-dev@orb "tmux new -As ${(q)session}"' \
    "$ROOT/config/zsh/air.zsh" || fail "personal development VM function is incorrect"
  rg -Fqx "alias work-devs='ssh work-dev@orb \"tmux ls\"'" \
    "$ROOT/config/zsh/air.zsh" || fail "work development session-list alias is missing"
  rg -Fqx "alias personal-devs='ssh personal-dev@orb \"tmux ls\"'" \
    "$ROOT/config/zsh/air.zsh" || fail "personal development session-list alias is missing"
  rg -qx 'MAC_ORBSTACK_API_BRIDGE=enabled' \
    "$ROOT/profiles/work-mini.env" || fail "work OrbStack API bridge is not enabled"
  rg -qx 'MAC_ORBSTACK_API_BRIDGE=disabled' \
    "$ROOT/profiles/personal-mini.env" || fail "personal OrbStack API bridge is not disabled"
  for mini_profile in personal-mini work-mini; do
    rg -qx 'MAC_LOCAL_DEV_TLS=enabled' "$ROOT/profiles/$mini_profile.env" \
      || fail "$mini_profile local development TLS is not enabled"
  done

  if rg -i '(grok|edge|whatsapp|moom|aseprite|adguard|imovie|recordly|cursor|github-desktop|redis-insight)' \
    "$ROOT/config"/Brewfile.* "$ROOT/config/app-store.air.tsv" "$ROOT/profiles"; then
    fail "an explicitly excluded application appears in a profile"
  fi

  if rg -i '(docker|colima|podman)' "$ROOT/config" "$ROOT/profiles"; then
    fail "an excluded container runtime appears in a profile"
  fi

  if rg -v '^(brew "(bat|fd|fzf|mas|mkcert|ripgrep|starship|zoxide|zsh-autosuggestions|zsh-syntax-highlighting)"|cask "[a-z0-9@+._-]+"|[[:space:]]*|#.*)$' "$ROOT/config"/Brewfile.*; then
    fail "a Brewfile contains an unexpected entry"
  fi

  if rg '(brew bundle cleanup|brew uninstall|mas uninstall)' "$ROOT/bin" "$ROOT/bootstrap"; then
    fail "an application removal command is present"
  fi

  if rg 'defaults[[:space:]]+write' "$ROOT/bin" "$ROOT/bootstrap"; then
    fail "an unreviewed macOS default is being changed"
  fi

  if git -C "$ROOT" grep -nIiE \
    '(BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-(proj-)?[A-Za-z0-9_-]{20,}|xai-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}|password[[:space:]]*=|token[[:space:]]*=)' \
    -- . ':!tests/test-static.sh'; then
    fail "a possible secret is present"
  fi

  if git -C "$ROOT" grep -nE '/Users/[[:alnum:]_.-]+/' -- . ':!tests/test-static.sh'; then
    fail "a local macOS home path is tracked"
  fi

  if git -C "$ROOT" ls-files \
    | rg -q '(^|/)(rootCA-key\.pem|localhost-key\.pem|localhost\.pfx(-password)?)$'; then
    fail "generated TLS private material is tracked"
  fi

  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT" diff --check
  fi

  printf 'ok: static policy and syntax checks\n'
}

main "$@"
