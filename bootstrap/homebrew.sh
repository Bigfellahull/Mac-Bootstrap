#!/usr/bin/env bash

set -Eeuo pipefail

# shellcheck source=bootstrap/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_command_line_tools() {
  xcode-select -p >/dev/null 2>&1 \
    || die "Xcode Command Line Tools are not installed. Install them before running bootstrap."
}

require_homebrew() {
  homebrew_binary >/dev/null 2>&1 \
    || die "Homebrew is not installed. Install it from https://brew.sh before running bootstrap."
}

main() {
  require_macos
  require_command_line_tools
  require_homebrew
  activate_homebrew
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
