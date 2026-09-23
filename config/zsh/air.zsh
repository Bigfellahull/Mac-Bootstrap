unalias work-dev 2>/dev/null || true
unalias personal-dev 2>/dev/null || true
unalias work-image 2>/dev/null || true
unalias personal-image 2>/dev/null || true

# Attach to a work VM tmux session through the managed SSH alias.
work-dev() {
  local session="${1:-dev}"
  ssh -t work-dev "tmux new -As ${(q)session}"
}

# Attach to a personal VM tmux session through the managed SSH alias.
personal-dev() {
  local session="${1:-dev}"
  ssh -t personal-dev "tmux new -As ${(q)session}"
}

# Send a clipboard image to the work VM, or clean its stored images.
work-image() {
  "$HOME/.config/mac-bootstrap/dev-image" "${1-send}" work-dev "${@:2}"
}

# Send a clipboard image to the personal VM, or clean its stored images.
personal-image() {
  "$HOME/.config/mac-bootstrap/dev-image" "${1-send}" personal-dev "${@:2}"
}

alias work-devs='ssh work-dev "tmux ls"'
alias personal-devs='ssh personal-dev "tmux ls"'
