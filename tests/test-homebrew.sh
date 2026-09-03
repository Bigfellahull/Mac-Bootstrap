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
  local brew_log
  local prerequisite_log
  local warnings

  test_directory="$(mktemp -d "${TMPDIR:-/tmp}/mac-bootstrap-homebrew-test.XXXXXX")"
  brew_log="$test_directory/brew.log"
  prerequisite_log="$test_directory/prerequisite.log"

  if (
    # shellcheck source=bootstrap/homebrew.sh
    source "$ROOT/bootstrap/homebrew.sh"
    xcode-select() {
      printf '%s\n' "$*" >> "$prerequisite_log"
      return 1
    }
    require_command_line_tools >/dev/null 2>&1
  ); then
    fail "missing Command Line Tools were accepted"
  fi
  grep -Fxq -- '-p' "$prerequisite_log" || fail "Command Line Tools were not checked"
  if grep -Fq -- '--install' "$prerequisite_log"; then
    fail "bootstrap initiated Command Line Tools installation"
  fi

  (
    # shellcheck source=bootstrap/applications.sh
    source "$ROOT/bootstrap/applications.sh"
    brew() {
      printf 'auto_update=%s args=%s\n' "${HOMEBREW_NO_AUTO_UPDATE:-}" "$*" >> "$brew_log"
    }
    install_brewfile config/Brewfile.common >/dev/null
  )
  grep -Fq 'args=bundle install --no-upgrade --file ' "$brew_log" \
    || fail "Homebrew apply can upgrade installed dependencies"

  (
    # shellcheck source=bootstrap/verify.sh
    source "$ROOT/bootstrap/verify.sh"
    brew() {
      printf 'auto_update=%s args=%s\n' "${HOMEBREW_NO_AUTO_UPDATE:-}" "$*" >> "$brew_log"
    }
    verify_brewfile config/Brewfile.common >/dev/null
  )
  grep -Fq 'auto_update=1 args=bundle check --no-upgrade --file=' "$brew_log" \
    || fail "Homebrew verification can mutate or report harmless outdated dependencies"

  (
    # shellcheck source=bootstrap/verify.sh
    source "$ROOT/bootstrap/verify.sh"
    MAC_APP_STORE_FILE=config/app-store.air.tsv
    mas() {
      return 42
    }
    verify_app_store >/dev/null 2>&1
    [[ "$verification_failed" -eq 1 ]]
  ) || fail "a failed Mac App Store listing aborted aggregate verification"

  mkdir -p "$test_directory/home/Applications/Podman Desktop.app" \
    "$test_directory/home/Applications/OrbStack.app"
  warnings="$(
    # shellcheck source=bootstrap/verify.sh
    source "$ROOT/bootstrap/verify.sh"
    HOME="$test_directory/home"
    MAC_PROFILE_KIND=air
    warn_about_excluded_software 2>&1
  )"
  grep -Fq 'Podman is installed' <<<"$warnings" || fail "Podman warning is missing"
  grep -Fq 'OrbStack is installed' <<<"$warnings" || fail "Air OrbStack warning is missing"

  printf 'ok: Homebrew and verification policy\n'
}

trap cleanup EXIT
main "$@"
