#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=bootstrap/google-drive.sh
source "$ROOT/bootstrap/google-drive.sh"

test_directory=
fake_owner=
sudo_failure=0

# Remove only this test's temporary fixtures.
cleanup() {
  [[ -z "$test_directory" ]] || rm -rf "$test_directory"
}

# Report a failed assertion.
fail() {
  printf 'not ok: %s\n' "$*" >&2
  exit 1
}

# Simulate ownership defects without creating root-owned test files.
stat() {
  if [[ "$*" == "-f %u $google_support_directory" && -n "$fake_owner" ]]; then
    printf '%s\n' "$fake_owner"
  else
    /usr/bin/stat "$@"
  fi
}

# Check the privileged repair's exact scope without invoking sudo.
sudo() {
  [[ $# -eq 4 && "$1" == /usr/sbin/chown && "$2" == -h \
    && "$3" == "$(id -u):$(id -g)" && "$4" == "$google_support_directory" ]] \
    || fail "unexpected privileged command"
  printf 'repair\n' >> "$test_directory/sudo.log"
  [[ "$sudo_failure" == 0 ]] || return 1
  fake_owner="$(id -u)"
}

# Require rejection without creating or repairing a directory.
assert_rejected() {
  local description="$1"
  local before

  before="$(cat "$test_directory/sudo.log")"
  if (google_drive_apply >/dev/null 2>&1); then
    fail "$description was accepted"
  fi
  [[ "$(cat "$test_directory/sudo.log")" == "$before" ]] \
    || fail "$description triggered a privileged repair"
}

# Exercise fresh setup, repeat runs, repair scope and unsafe paths.
main() {
  local contents

  test_directory="$(mktemp -d "$ROOT/.google-drive-test.XXXXXX")"
  : > "$test_directory/sudo.log"
  google_support_directory="$test_directory/Library/Application Support/Google"

  if (google_drive_verify >/dev/null 2>&1); then
    fail "verification accepted a missing directory"
  fi
  [[ ! -e "$google_support_directory" ]] || fail "verification created a directory"

  google_drive_apply >/dev/null
  [[ -d "$google_support_directory" && -O "$google_support_directory" ]] \
    || fail "fresh setup did not create a user-owned Google directory"
  [[ ! -e "$google_support_directory/DriveFS" ]] || fail "setup created application state"
  google_drive_apply >/dev/null
  google_drive_verify
  [[ ! -s "$test_directory/sudo.log" ]] || fail "healthy setup invoked sudo"

  mkdir "$google_support_directory/DriveFS"
  printf 'preserve this application data\n' > "$google_support_directory/DriveFS/state"
  chmod 640 "$google_support_directory/DriveFS/state"
  contents="$(cksum "$google_support_directory/DriveFS/state")"
  fake_owner=0
  if (google_drive_verify >/dev/null 2>&1); then
    fail "verification accepted root ownership"
  fi
  [[ ! -s "$test_directory/sudo.log" ]] || fail "verification invoked sudo"
  google_drive_apply >/dev/null
  [[ "$(wc -l < "$test_directory/sudo.log" | tr -d ' ')" == 1 ]] \
    || fail "root ownership did not trigger exactly one repair"
  [[ "$(cksum "$google_support_directory/DriveFS/state")" == "$contents" \
    && "$(stat -f '%Lp' "$google_support_directory/DriveFS/state")" == 640 ]] \
    || fail "repair changed existing application data"
  google_drive_apply >/dev/null
  [[ "$(wc -l < "$test_directory/sudo.log" | tr -d ' ')" == 1 ]] \
    || fail "repeat apply repaired healthy ownership"

  fake_owner=0
  sudo_failure=1
  if (google_drive_apply >/dev/null 2>&1); then
    fail "a failed ownership repair was accepted"
  fi
  sudo_failure=0
  fake_owner=123456
  assert_rejected "another user's directory"
  fake_owner=

  chmod 777 "$google_support_directory"
  assert_rejected "a world-writable directory"
  chmod 700 "$google_support_directory"
  chmod +a 'everyone allow write' "$google_support_directory"
  assert_rejected "a directory with an ACL"
  chmod -N "$google_support_directory"

  mv "$google_support_directory" "$test_directory/saved-google"
  ln -s "$test_directory/saved-google" "$google_support_directory"
  assert_rejected "a symlinked Google directory"
  rm "$google_support_directory"
  touch "$google_support_directory"
  assert_rejected "a regular file"
  rm "$google_support_directory"

  mv "$test_directory/Library" "$test_directory/saved-library"
  ln -s "$test_directory/saved-library" "$test_directory/Library"
  assert_rejected "a symlinked ancestor"
  rm "$test_directory/Library"
  google_support_directory="$test_directory/mini/Google"
  google_drive_main apply personal-mini
  google_drive_main verify work-mini
  [[ ! -e "$google_support_directory" ]] || fail "mini setup created Google state"

  printf 'ok: Google Drive directory creation, ownership repair and read-only verification\n'
}

trap cleanup EXIT
main "$@"
