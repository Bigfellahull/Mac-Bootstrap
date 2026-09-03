unalias work-dev 2>/dev/null || true
unalias personal-dev 2>/dev/null || true

work-dev() {
  local session="${1:-dev}"
  ssh -t work-dev@orb "tmux new -As ${(q)session}"
}

personal-dev() {
  local session="${1:-dev}"
  ssh -t personal-dev@orb "tmux new -As ${(q)session}"
}

alias work-devs='ssh work-dev@orb "tmux ls"'
alias personal-devs='ssh personal-dev@orb "tmux ls"'
