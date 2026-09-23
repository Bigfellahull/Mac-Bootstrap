#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_directory=

fail() {
  printf 'not ok: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local value="$1"
  local expected="$2"

  grep -Fq "$expected" <<<"$value" || fail "expected output to contain: $expected"
}

assert_not_contains() {
  local value="$1"
  local unexpected="$2"

  if grep -Fiq "$unexpected" <<<"$value"; then
    fail "expected output not to contain: $unexpected"
  fi
}

main() {
  local profiles
  local air
  local personal
  local work
  local tmux_session_command

  test_directory="$(mktemp -d "${TMPDIR:-/tmp}/mac-bootstrap-cli-test.XXXXXX")"
  trap 'rm -rf "$test_directory"' EXIT

  # The plan must preserve zsh's session-quoting expression literally.
  # shellcheck disable=SC2016
  tmux_session_command='"tmux new -As ${(q)session}"'

  profiles="$("$ROOT/bin/mac" list)"
  [[ "$profiles" == $'air\npersonal-mini\nwork-mini' ]] || fail "profile list is incorrect"

  air="$("$ROOT/bin/mac" plan air)"
  assert_contains "$air" 'cask "tableplus"'
  assert_contains "$air" 'cask "alcove"'
  assert_contains "$air" 'cask "cleanshot"'
  assert_contains "$air" 'cask "fastmail"'
  assert_contains "$air" 'cask "microsoft-teams"'
  assert_contains "$air" 'cask "rectangle"'
  assert_contains "$air" 'brew "starship"'
  assert_contains "$air" $'361285480\tKeynote'
  assert_contains "$air" $'361304891\tNumbers'
  assert_contains "$air" $'361309726\tPages'
  assert_contains "$air" 'shell-integration-features = ssh-env,ssh-terminfo'
  assert_contains "$air" 'theme = dark:Catppuccin Frappe,light:Catppuccin Latte'
  assert_contains "$air" 'Managed Starship and zsh configuration:'
  assert_contains "$air" 'work-dev() {'
  assert_contains "$air" "ssh -t work-dev $tmux_session_command"
  assert_contains "$air" 'personal-dev() {'
  assert_contains "$air" "ssh -t personal-dev $tmux_session_command"
  assert_contains "$air" 'alias work-devs='"'"'ssh work-dev "tmux ls"'"'"''
  assert_contains "$air" 'alias personal-devs='"'"'ssh personal-dev "tmux ls"'"'"''
  assert_contains "$air" 'Managed Air SSH routing:'
  assert_contains "$air" 'using Tailscale everywhere'
  assert_not_contains "$air" 'cask "1password-cli"'
  assert_not_contains "$air" 'recordly'
  assert_not_contains "$air" 'datagrip'
  assert_not_contains "$air" 'orbstack'
  assert_not_contains "$air" 'OrbStack Docker API bridge'
  assert_not_contains "$air" 'Local development TLS'
  assert_not_contains "$air" 'parallels'
  assert_not_contains "$air" 'grok'

  personal="$("$ROOT/bin/mac" plan personal-mini)"
  assert_contains "$personal" 'cask "1password"'
  assert_contains "$personal" 'cask "orbstack"'
  assert_not_contains "$personal" 'tableplus'
  assert_not_contains "$personal" 'fastmail'
  assert_not_contains "$personal" 'parallels'
  assert_not_contains "$personal" 'shell-integration-features'
  assert_contains "$personal" 'brew "starship"'
  assert_contains "$personal" 'cask "1password-cli"'
  assert_contains "$personal" 'Managed Starship and zsh configuration:'
  assert_contains "$personal" 'compinit'
  assert_not_contains "$personal" 'work-dev()'
  assert_not_contains "$personal" 'personal-dev()'
  assert_not_contains "$personal" 'dev-image'
  assert_not_contains "$personal" 'cask "ghostty"'
  assert_contains "$personal" 'OrbStack Docker API bridge:'
  assert_contains "$personal" 'state: disabled'
  assert_contains "$personal" 'Local development TLS:'
  assert_contains "$personal" 'bin/local-dev-tls init personal-mini'

  work="$("$ROOT/bin/mac" plan work-mini)"
  assert_contains "$work" 'cask "1password"'
  assert_contains "$work" 'cask "orbstack"'
  assert_contains "$work" 'cask "parallels"'
  assert_contains "$work" 'OrbStack Docker API bridge:'
  assert_contains "$work" 'state: enabled'
  assert_contains "$work" 'orbstack-docker-api-work-mini'
  assert_contains "$work" 'Local development TLS:'
  assert_contains "$work" 'bin/local-dev-tls init work-mini'
  assert_not_contains "$work" 'tableplus'
  assert_not_contains "$work" 'fastmail'
  assert_contains "$work" 'brew "starship"'
  assert_contains "$work" 'cask "1password-cli"'
  assert_contains "$work" 'Managed Starship and zsh configuration:'
  assert_contains "$work" 'compinit'
  assert_not_contains "$work" 'work-dev()'
  assert_not_contains "$work" 'personal-dev()'
  assert_not_contains "$work" 'dev-image'
  assert_not_contains "$work" 'cask "ghostty"'

  if "$ROOT/bin/mac" plan unknown >/dev/null 2>&1; then
    fail "unknown profile was accepted"
  fi
  if "$ROOT/bin/mac" plan ../profiles/air >/dev/null 2>&1; then
    fail "profile path traversal was accepted"
  fi
  mkdir -p "$test_directory/invalid/profiles" \
    "$test_directory/air-as-mini/profiles" \
    "$test_directory/mini-as-air/profiles"
  sed 's/MAC_PROFILE_KIND=air/MAC_PROFILE_KIND=ari/' \
    "$ROOT/profiles/air.env" >"$test_directory/invalid/profiles/air.env"
  if bash -Eeuo pipefail -c \
    'source "$1/bootstrap/lib.sh"; MAC_BOOTSTRAP_ROOT="$2"; load_profile air' \
    _ "$ROOT" "$test_directory/invalid" >/dev/null 2>&1; then
    fail "invalid profile kind was accepted"
  fi
  sed 's/MAC_PROFILE_KIND=air/MAC_PROFILE_KIND=mini/' \
    "$ROOT/profiles/air.env" >"$test_directory/air-as-mini/profiles/air.env"
  if bash -Eeuo pipefail -c \
    'source "$1/bootstrap/lib.sh"; MAC_BOOTSTRAP_ROOT="$2"; load_profile air' \
    _ "$ROOT" "$test_directory/air-as-mini" >/dev/null 2>&1; then
    fail "Air profile was accepted as a mini"
  fi
  sed 's/MAC_PROFILE_KIND=mini/MAC_PROFILE_KIND=air/' \
    "$ROOT/profiles/work-mini.env" >"$test_directory/mini-as-air/profiles/work-mini.env"
  if bash -Eeuo pipefail -c \
    'source "$1/bootstrap/lib.sh"; MAC_BOOTSTRAP_ROOT="$2"; load_profile work-mini' \
    _ "$ROOT" "$test_directory/mini-as-air" >/dev/null 2>&1; then
    fail "mini profile was accepted as an Air"
  fi

  printf 'ok: CLI profile plans\n'
}

main "$@"
