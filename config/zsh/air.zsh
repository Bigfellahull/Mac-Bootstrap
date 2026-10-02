unalias work-dev 2>/dev/null || true
unalias personal-dev 2>/dev/null || true
unalias work-image 2>/dev/null || true
unalias personal-image 2>/dev/null || true

# Run in a subshell so signal traps and terminal state stay local to this connection.
_mac_bootstrap_tmux() (
  emulate -L zsh
  local host="$1" session="${2:-dev}"
  local result=0 delay=2 terminal_state= remote_command
  local -a delays=(2 5 10 15)
  local attempt=1

  _mac_bootstrap_terminal_cleanup() {
    if [[ -t 1 ]]; then
      # Leave remote mouse/focus/paste modes and the alternate screen behind.
      printf '\033[?1000l\033[?1002l\033[?1003l\033[?1005l\033[?1006l\033[?1015l\033[?1016l\033[?1004l\033[?2004l\033[?1049l\033[0m\033[?25h'
      [[ -z "$terminal_state" ]] || command stty "$terminal_state" < /dev/tty 2>/dev/null
    fi
    return 0
  }

  if [[ -t 0 && -t 1 ]]; then
    terminal_state="$(command stty -g < /dev/tty 2>/dev/null)"
  fi
  trap '_mac_bootstrap_terminal_cleanup' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  trap 'exit 129' HUP

  remote_command="tmux new -As ${(q)session}"
  while true; do
    # Bypass terminal wrappers: setup must never replay the remote command.
    # Disable multiplexing so the lifetime and exit status belong to this client.
    if command ssh -t -o ControlMaster=no -o ControlPath=none \
        -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
        "$host" "$remote_command"; then
      result=0
    else
      result=$?
    fi
    _mac_bootstrap_terminal_cleanup
    if (( result != 255 )); then
      if (( result != 0 )); then
        print -u2 -- "Remote tmux command ended (status $result). Check the session with ${host}s."
      fi
      exit "$result"
    fi

    # Exact-name attachment avoids tmux selecting a similarly named session.
    # Never create a replacement session during recovery.
    remote_command="tmux attach-session -t ${(q):-=$session}"
    delay=$delays[$attempt]
    print -u2 -- "SSH connection to $host failed. Reattaching to '$session' in ${delay}s; Ctrl+C to stop."
    command sleep "$delay"
    (( attempt < ${#delays} )) && (( attempt++ ))
  done
)

# Create or attach once; reconnect to that session after an SSH failure.
work-dev() {
  _mac_bootstrap_tmux work-dev "${1:-dev}"
}

personal-dev() {
  _mac_bootstrap_tmux personal-dev "${1:-dev}"
}

# Send a clipboard image to the work VM, or clean its stored images.
work-image() {
  "$HOME/.config/mac-bootstrap/dev-image" "${1-send}" work-dev "${@:2}"
}

# Send a clipboard image to the personal VM, or clean its stored images.
personal-image() {
  "$HOME/.config/mac-bootstrap/dev-image" "${1-send}" personal-dev "${@:2}"
}

# Bypass terminal SSH wrappers for one-shot commands to avoid setup replay.
alias work-devs='command ssh work-dev "tmux ls"'
alias personal-devs='command ssh personal-dev "tmux ls"'
