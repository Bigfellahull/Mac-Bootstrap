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

if command -v bat >/dev/null 2>&1; then
  export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:500 {}'"
fi

if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

if [[ -n "${HOMEBREW_PREFIX:-}" ]]; then
  mac_bootstrap_homebrew_prefix="$HOMEBREW_PREFIX"
elif [[ -d /opt/homebrew ]]; then
  mac_bootstrap_homebrew_prefix=/opt/homebrew
else
  mac_bootstrap_homebrew_prefix=/usr/local
fi

if [[ -r "$mac_bootstrap_homebrew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$mac_bootstrap_homebrew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

if [[ -r "$mac_bootstrap_homebrew_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$mac_bootstrap_homebrew_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

unset mac_bootstrap_homebrew_prefix
