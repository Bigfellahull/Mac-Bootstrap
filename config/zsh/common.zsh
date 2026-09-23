if [[ -n "${HOMEBREW_PREFIX:-}" ]]; then
  mac_bootstrap_homebrew_prefix="$HOMEBREW_PREFIX"
elif [[ -d /opt/homebrew ]]; then
  mac_bootstrap_homebrew_prefix=/opt/homebrew
else
  mac_bootstrap_homebrew_prefix=/usr/local
fi

# SSH login shells need Homebrew tools and completions on their search paths.
if [[ -d "$mac_bootstrap_homebrew_prefix/bin" ]]; then
  typeset -U path fpath
  path=("$mac_bootstrap_homebrew_prefix/bin" "$mac_bootstrap_homebrew_prefix/sbin" $path)
  fpath=("$mac_bootstrap_homebrew_prefix/share/zsh/site-functions" $fpath)
fi

if (( ! $+functions[compdef] )); then
  autoload -Uz compinit
  compinit
fi

if command -v bat >/dev/null 2>&1; then
  export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers --line-range=:500 {}'"
fi

if command -v fzf >/dev/null 2>&1; then
  source <(fzf --zsh)
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

if [[ -r "$mac_bootstrap_homebrew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "$mac_bootstrap_homebrew_prefix/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

if [[ -r "$mac_bootstrap_homebrew_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "$mac_bootstrap_homebrew_prefix/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

unset mac_bootstrap_homebrew_prefix
