#!/usr/bin/env bash

set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_directory=

# Remove the isolated homes used by this suite.
cleanup() {
  [[ -z "$test_directory" ]] || rm -rf "$test_directory"
}

# Stop on a failed behavioural assertion.
fail() {
  printf 'not ok: %s\n' "$*" >&2
  exit 1
}

# Run bootstrap against a disposable home without touching real SSH state.
run_ssh() {
  HOME="$test_directory/home" "$ROOT/bootstrap/ssh.sh" "$@"
}

# Supply fixture identities, never real account information.
write_settings() {
  mkdir -p "$test_directory/home/.config/mac-bootstrap"
  printf 'work\twork-mini.test-tailnet.ts.net\twork_mac\twork_linux\n' > "$test_directory/settings"
  printf 'personal\tpersonal-mini.test-tailnet.ts.net\tpersonal_mac\tpersonal_linux\n' >> "$test_directory/settings"
  cp "$test_directory/settings" "$test_directory/home/.config/mac-bootstrap/ssh-air.tsv"
}

# Exercise OpenSSH parsing, preservation, isolation and failure paths offline.
main() {
  local settings
  local fragment
  local config
  local resolved
  local profile
  local original_sum

  if [[ "$(uname -s)" != Darwin ]]; then
    printf 'skip: SSH configuration tests require macOS\n'
    return
  fi
  test_directory="$(mktemp -d "${TMPDIR:-/tmp}/mac-bootstrap-ssh-test.XXXXXX")"
  mkdir -p "$test_directory/home"
  settings="$test_directory/home/.config/mac-bootstrap/ssh-air.tsv"
  config="$test_directory/home/.ssh/config"
  fragment="$test_directory/home/.ssh/mac-bootstrap/air.conf"

  run_ssh plan air >/dev/null
  run_ssh apply air >/dev/null 2>&1
  if run_ssh verify air >/dev/null 2>&1; then fail "missing settings passed verification"; fi
  [[ ! -e "$test_directory/home/.ssh" ]] || fail "missing settings changed SSH state"

  write_settings
  for profile in personal-mini work-mini; do
    run_ssh apply "$profile"
    run_ssh verify "$profile"
  done
  [[ ! -e "$test_directory/home/.ssh" ]] || fail "mini profile installed Air routes"

  mkdir -m 700 "$test_directory/home/.ssh"
  printf 'ServerAliveInterval 99\nHost unrelated\n  HostName elsewhere.example\n' > "$config"
  chmod 640 "$config"
  cp "$config" "$test_directory/original"
  run_ssh apply air >/dev/null
  run_ssh verify air >/dev/null
  tail -n +5 "$config" | cmp -s - "$test_directory/original" || fail "existing configuration changed"
  [[ "$(stat -f '%Lp' "$config")" == 640 ]] || fail "existing config permissions changed"
  [[ "$(stat -f '%Lp' "$fragment")" == 600 ]] || fail "fragment is not private"
  original_sum="$(cksum "$config" "$fragment")"
  run_ssh apply air >/dev/null
  run_ssh verify air >/dev/null
  [[ "$(cksum "$config" "$fragment")" == "$original_sum" ]] || fail "apply is not idempotent"

  # OpenSSH expands tilde from the account database, not the HOME test override.
  sed "s|~/.ssh/mac-bootstrap/air.conf|$fragment|" "$config" > "$test_directory/effective.conf"
  for profile in work personal; do
    resolved="$(/usr/bin/ssh -G -F "$test_directory/effective.conf" "$profile-dev" 2>/dev/null)"
    for expected in 'hostname 127.0.0.1' 'port 32222' "user ${profile}_linux@$profile-dev" \
      "proxyjump $profile-mini" "hostkeyalias $profile-dev-via-$profile-mini" \
      "identityfile ~/.ssh/$profile-mini_ed25519" 'identitiesonly yes' 'forwardagent no' \
      'serveraliveinterval 30' 'serveralivecountmax 3' 'controlmaster false'; do
      grep -Fxq "$expected" <<< "$resolved" || fail "$profile-dev is missing $expected"
    done
    [[ "$(grep -c '^identityfile ' <<< "$resolved")" == 1 ]] || fail "VM identity is not isolated"
    resolved="$(/usr/bin/ssh -G -F "$test_directory/effective.conf" "$profile-mini" 2>/dev/null)"
    for expected in "hostname $profile-mini.test-tailnet.ts.net" 'port 22' "user ${profile}_mac" \
      "identityfile ~/.ssh/$profile-mini_ed25519"; do
      grep -Fxq "$expected" <<< "$resolved" || fail "$profile-mini is missing $expected"
    done
  done
  resolved="$(/usr/bin/ssh -G -F "$test_directory/effective.conf" unrelated 2>/dev/null)"
  grep -Fxq 'hostname elsewhere.example' <<< "$resolved" || fail "unrelated host was changed"
  grep -Fxq 'serveraliveinterval 99' <<< "$resolved" || fail "original global scope was lost"

  printf '\nMatch exec "touch %s/should-not-exist"\n' "$test_directory" >> "$config"
  run_ssh verify air >/dev/null
  [[ ! -e "$test_directory/should-not-exist" ]] || fail "verification executed user commands"

  sed 's/work_linux/updated_linux/' "$settings" > "$test_directory/updated"
  cp "$test_directory/updated" "$settings"
  if run_ssh verify air >/dev/null 2>&1; then fail "settings drift was not detected"; fi
  run_ssh apply air >/dev/null
  run_ssh verify air >/dev/null
  grep -Fq 'User updated_linux@work-dev' "$fragment" || fail "updated settings were not installed"

  original_sum="$(cksum "$config" "$fragment")"
  for invalid in placeholders duplicate missing shared-host local-host injection empty-field; do
    cp "$test_directory/settings" "$settings"
    case "$invalid" in
      placeholders) cp "$ROOT/config/ssh/air.tsv.example" "$settings" ;;
      duplicate) cat "$test_directory/settings" >> "$settings" ;;
      missing) head -n 1 "$test_directory/settings" > "$settings" ;;
      shared-host) sed 's/personal-mini/work-mini/' "$test_directory/settings" > "$settings" ;;
      local-host) sed 's/work-mini.test-tailnet.ts.net/work-mini.local/' "$test_directory/settings" > "$settings" ;;
      injection)
        # shellcheck disable=SC2016
        printf 'work\twork-mini.test-tailnet.ts.net\t$(touch bad)\tlinux\n' > "$settings"
        ;;
      empty-field) sed 's/work_mac//' "$test_directory/settings" > "$settings" ;;
    esac
    if run_ssh apply air >/dev/null 2>&1; then fail "$invalid settings were accepted"; fi
    [[ "$(cksum "$config" "$fragment")" == "$original_sum" ]] || fail "invalid settings changed SSH state"
  done
  cp "$test_directory/settings" "$settings"

  printf '# mac-bootstrap: managed Air SSH routing\n' >> "$config"
  original_sum="$(cksum "$config" "$fragment")"
  if run_ssh apply air >/dev/null 2>&1; then fail "incomplete managed block was accepted"; fi
  [[ "$(cksum "$config" "$fragment")" == "$original_sum" ]] || fail "malformed block caused changes"
  sed '$d' "$config" > "$test_directory/repaired"
  cp "$test_directory/repaired" "$config"

  mv "$fragment" "$test_directory/saved-fragment"
  ln -s "$test_directory/saved-fragment" "$fragment"
  if run_ssh apply air >/dev/null 2>&1; then fail "symlinked fragment was accepted"; fi
  rm "$fragment"
  mv "$test_directory/saved-fragment" "$fragment"
  chmod 666 "$settings"
  if run_ssh apply air >/dev/null 2>&1; then fail "unsafe settings permissions were accepted"; fi
  chmod 600 "$settings"
  mv "$test_directory/home/.ssh" "$test_directory/elsewhere"
  ln -s "$test_directory/elsewhere" "$test_directory/home/.ssh"
  if run_ssh apply air >/dev/null 2>&1; then fail "symlinked SSH directory was accepted"; fi

  printf 'ok: Air SSH routing, preservation and offline verification\n'
}

trap cleanup EXIT
main "$@"
