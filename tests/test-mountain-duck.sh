#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { printf 'skip: Mountain Duck tests require macOS\n'; exit 0; }
test_directory="$(mktemp -d "${TMPDIR:-/tmp}/mac-bootstrap-duck-test.XXXXXX")"
trap 'rm -rf "$test_directory"' EXIT
export HOME="$test_directory/home"
mkdir -p "$HOME/.config/mac-bootstrap" "$test_directory/bin"
# Isolate app-running checks from the real desktop.
# The stub evaluates this variable when executed.
# shellcheck disable=SC2016
printf '#!/bin/sh\nexit "${DUCK_TEST_RUNNING:-1}"\n' > "$test_directory/bin/pgrep"
chmod +x "$test_directory/bin/pgrep"
export PATH="$test_directory/bin:$PATH"
fail() { printf 'not ok: %s\n' "$*" >&2; exit 1; }
run() { "$ROOT/bootstrap/mountain-duck.sh" "$@"; }
run apply air >/dev/null 2>&1
if run verify air >/dev/null 2>&1; then fail 'missing settings accepted'; fi
printf 'work\twork-mini.test-tailnet.ts.net\twork_mac\twork_linux\npersonal\tpersonal-mini.test-tailnet.ts.net\tpersonal_mac\tpersonal_linux\n' > "$HOME/.config/mac-bootstrap/ssh-air.tsv"
"$ROOT/bootstrap/ssh.sh" apply air >/dev/null
for profile in work-mini personal-mini; do run apply "$profile"; run verify "$profile"; done
[[ ! -d "$HOME/Library" ]] || fail 'mini changed files'
if DUCK_TEST_RUNNING=0 run apply air >/dev/null 2>&1; then fail 'running app accepted'; fi
run apply air >/dev/null
run verify air >/dev/null
bookmarks="$HOME/Library/Group Containers/G69SCX94XU.duck/Library/Application Support/duck/Bookmarks"
work="$bookmarks/EB02D0D1-44D3-4C22-86FB-28BDFD051A41.duck"
personal="$bookmarks/D782E44A-3D37-41CA-8269-F5A901F56BF0.duck"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :Username' "$work")" == work_linux@work-dev ]] || fail 'work identity'
[[ "$(/usr/libexec/PlistBuddy -c 'Print :Path' "$personal")" == /home/personal_linux ]] || fail 'personal path'
# Match the literal bookmark path, not an expanded home.
# shellcheck disable=SC2088
[[ "$(/usr/bin/plutil -extract 'Private Key File' raw -o - "$personal")" == '~/.ssh/personal-mini_ed25519' ]] || fail 'personal key'
[[ "$(stat -f '%Lp' "$work")" == 600 ]] || fail 'bookmark permissions'
printf 'unrelated\n' > "$bookmarks/unrelated.duck"
/usr/bin/plutil -insert Custom -json '{"test.preference":"keep"}' "$work"
before="$(cksum "$work" "$personal" "$bookmarks/unrelated.duck")"
run apply air >/dev/null
[[ "$before" == "$(cksum "$work" "$personal" "$bookmarks/unrelated.duck")" ]] || fail 'not idempotent or changed user state'
/usr/bin/plutil -replace Path -string /wrong "$personal"
if run verify air >/dev/null 2>&1; then fail 'drift accepted'; fi
run apply air >/dev/null
run verify air >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :Custom:test.preference' "$work")" == keep ]] || fail 'app setting removed'
mv "$personal" "$test_directory/saved.duck"
ln -s "$test_directory/saved.duck" "$personal"
if run apply air >/dev/null 2>&1; then fail 'symlink accepted'; fi
printf 'ok: Mountain Duck bookmarks, isolation, preservation, drift and symlink rejection\n'
