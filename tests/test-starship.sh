#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_directory=

cleanup() {
  if [[ -n "$test_directory" ]]; then
    rm -rf "$test_directory"
  fi
}

fail() {
  printf 'not ok: %s\n' "$*" >&2
  exit 1
}

main() {
  local actual
  local existing_home
  local inactive_home
  local init_line
  local new_home
  local personal_home
  local source_line
  local symlink_home

  # shellcheck disable=SC2016
  init_line='eval "$(starship init zsh)"'
  # shellcheck disable=SC2016
  source_line='[[ -r "$HOME/.config/mac-bootstrap/air.zsh" ]] && source "$HOME/.config/mac-bootstrap/air.zsh"'

  if [[ "$(uname -s)" != Darwin ]]; then
    printf 'skip: Starship configuration tests require macOS\n'
    return
  fi

  zsh -n "$ROOT/config/zsh/air.zsh"
  test_directory="$(mktemp -d "${TMPDIR:-/tmp}/mac-bootstrap-starship-test.XXXXXX")"

  new_home="$test_directory/new-home"
  mkdir -p "$new_home"
  HOME="$new_home" "$ROOT/bootstrap/starship.sh" apply air >/dev/null
  cmp -s "$ROOT/config/starship.toml" "$new_home/.config/starship.toml" || \
    fail "Starship config is incorrect"
  cmp -s "$ROOT/config/zsh/air.zsh" "$new_home/.config/mac-bootstrap/air.zsh" || \
    fail "managed zsh config is incorrect"
  cmp -s "$ROOT/bin/dev-image" "$new_home/.config/mac-bootstrap/dev-image" || \
    fail "image helper is incorrect"
  [[ -x "$new_home/.config/mac-bootstrap/dev-image" ]] || fail "image helper is not executable"
  grep -Fxq "$init_line" "$new_home/.zshrc" || \
    fail "Starship zsh initialization is missing"
  grep -Fxq "$source_line" "$new_home/.zshrc" || \
    fail "managed zsh config is not loaded"
  HOME="$new_home" "$ROOT/bootstrap/starship.sh" verify air || \
    fail "Starship config did not verify"
  HOME="$new_home" "$ROOT/bootstrap/starship.sh" apply air >/dev/null
  [[ "$(grep -Fc "$init_line" "$new_home/.zshrc")" -eq 1 ]] || \
    fail "Starship zsh initialization was duplicated"
  [[ "$(grep -Fc "$source_line" "$new_home/.zshrc")" -eq 1 ]] || \
    fail "managed zsh source line was duplicated"

  actual="$(HOME="$new_home" zsh -fc '
    ssh() { printf "%s\n" "$@"; }
    source "$HOME/.config/mac-bootstrap/air.zsh"
    work-dev "feature branch"
  ')"
  [[ "$actual" == $'-t\nwork-dev\ntmux new -As feature\\ branch' ]] || \
    fail "work development VM function did not quote the requested session"

  actual="$(HOME="$new_home" zsh -fc '
    ssh() { printf "%s\n" "$@"; }
    source "$HOME/.config/mac-bootstrap/air.zsh"
    personal-dev
  ')"
  [[ "$actual" == $'-t\npersonal-dev\ntmux new -As dev' ]] || \
    fail "personal development VM function did not use the default session"

  actual="$(HOME="$new_home" zsh -fc '
    ssh() { printf "%s\n" "$@"; }
    source "$HOME/.config/mac-bootstrap/air.zsh"
    eval work-devs
    eval personal-devs
  ')"
  [[ "$actual" == $'work-dev\ntmux ls\npersonal-dev\ntmux ls' ]] || \
    fail "development VM session-list aliases are incorrect"

  actual="$(HOME="$new_home" zsh -fc '
    source "$HOME/.config/mac-bootstrap/air.zsh"
    work-image --help
    personal-image --help
  ')"
  [[ "$actual" == *'work-image clean [--older-than Nd]'* && "$actual" == *'personal-image clean [--older-than Nd]'* ]] || \
    fail "image helper function does not invoke the installed executable"
  cat > "$new_home/.config/mac-bootstrap/dev-image" <<'EOF'
#!/usr/bin/env bash
printf '<%s>\n' "$@"
EOF
  actual="$(HOME="$new_home" zsh -fc '
    source "$HOME/.config/mac-bootstrap/air.zsh"
    work-image
    personal-image
    work-image clean
    personal-image clean --older-than 30d
    work-image clean --older-than "30 d"
  ')"
  [[ "$actual" == $'<send>\n<work-dev>\n<send>\n<personal-dev>\n<clean>\n<work-dev>\n<clean>\n<personal-dev>\n<--older-than>\n<30d>\n<clean>\n<work-dev>\n<--older-than>\n<30 d>' ]] || \
    fail "image commands did not preserve the action, VM or argument boundaries"

  if HOME="$new_home" "$ROOT/bootstrap/starship.sh" verify air; then
    fail "stale image helper was accepted"
  fi
  HOME="$new_home" "$ROOT/bootstrap/starship.sh" apply air >/dev/null
  HOME="$new_home" "$ROOT/bootstrap/starship.sh" verify air || fail "image helper was not refreshed"
  rm "$new_home/.config/mac-bootstrap/dev-image"
  ln -s "$test_directory/elsewhere" "$new_home/.config/mac-bootstrap/dev-image"
  if HOME="$new_home" "$ROOT/bootstrap/starship.sh" apply air >/dev/null 2>&1; then
    fail "symlinked image helper was accepted"
  fi

  existing_home="$test_directory/existing-home"
  mkdir -p "$existing_home/.config"
  printf '%s\n' '# existing shell configuration' > "$existing_home/.zshrc"
  printf '%s\n' "format = \"\$character\"" > "$existing_home/.config/starship.toml"
  chmod 640 "$existing_home/.zshrc"
  HOME="$existing_home" "$ROOT/bootstrap/starship.sh" apply air >/dev/null
  grep -Fxq '# existing shell configuration' "$existing_home/.zshrc" || \
    fail "existing zsh configuration was not preserved"
  grep -Fxq "$source_line" "$existing_home/.zshrc" || \
    fail "managed zsh config was not added to existing zsh configuration"
  [[ "$(stat -f '%Lp' "$existing_home/.zshrc")" == 640 ]] || \
    fail "zsh config permissions changed"
  cmp -s "$ROOT/config/starship.toml" "$existing_home/.config/starship.toml" || \
    fail "managed Starship preferences were not updated"

  inactive_home="$test_directory/inactive-home"
  mkdir -p "$inactive_home"
  printf '%s\n' \
    'if false; then' \
    "$init_line" \
    "$source_line" \
    'fi' > "$inactive_home/.zshrc"
  HOME="$inactive_home" "$ROOT/bootstrap/starship.sh" apply air >/dev/null
  HOME="$inactive_home" "$ROOT/bootstrap/starship.sh" verify air || \
    fail "inactive legacy zsh integration was not repaired"
  actual="$(HOME="$inactive_home" zsh -fc '
    starship() { return 0; }
    source "$HOME/.zshrc"
    whence -w work-dev
  ')"
  [[ "$actual" == 'work-dev: function' ]] || \
    fail "managed zsh integration does not execute at top level"

  symlink_home="$test_directory/symlink-home"
  mkdir -p "$symlink_home/.config"
  ln -s "$test_directory/elsewhere" "$symlink_home/.config/starship.toml"
  if HOME="$symlink_home" "$ROOT/bootstrap/starship.sh" apply air >/dev/null 2>&1; then
    fail "symlinked Starship config was accepted"
  fi

  personal_home="$test_directory/personal-home"
  mkdir -p "$personal_home"
  HOME="$personal_home" "$ROOT/bootstrap/starship.sh" apply personal-mini
  [[ ! -e "$personal_home/.config/starship.toml" ]] || \
    fail "Starship config was applied to a mini profile"
  [[ ! -e "$personal_home/.config/mac-bootstrap/air.zsh" ]] || \
    fail "managed zsh config was applied to a mini profile"
  [[ ! -e "$personal_home/.config/mac-bootstrap/dev-image" ]] || \
    fail "image helper was installed on a mini profile"

  printf 'ok: Starship Air configuration\n'
}

trap cleanup EXIT
main "$@"
