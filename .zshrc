# shellcheck shell=bash
# shellcheck disable=SC2034,SC1091

export DOTFILES_DIR="$HOME/dotfiles"
export EDITOR="nvim"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source "$ZSH/oh-my-zsh.sh"

eval "$(/opt/homebrew/bin/brew shellenv)"
eval "$(mise activate zsh)"
eval "$(zoxide init zsh --cmd cd)"

alias be="bundle exec"
alias bs="brew search"
alias cat="bat"
alias find="fd"
alias grep="rg"
alias la="eza -lah --icons=auto --git"
alias lg="lazygit"
alias ll="eza -lh --icons=auto --git"
alias ls="eza --icons=auto"
alias tree="eza --tree --icons=auto"
alias upd="brew update && brew upgrade --cask --greedy && brew upgrade && brew autoremove && brew cleanup && brew doctor"

bi() {
  check_github_auth || return 1
  brew install "$@" && sync_dots "Install $*"
}

bu() {
  check_github_auth || return 1
  brew uninstall "$@" && sync_dots "Uninstall $*"
}

check_github_auth() {
  if [[ ! -f "$HOME/.ssh/id_ed25519" ]]; then
    echo "error: ssh key missing at ~/.ssh/id_ed25519" >&2
    return 1
  fi
  if ! ssh -q -o BatchMode=yes -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo "error: github authentication failed" >&2
    return 1
  fi
  return 0
}

gcl() {
  local url="$1"
  local path="${url#git@github.com:}"
  path="${path#https://github.com/}"
  local account="${path%%/*}"
  local repo="${path##*/}"
  repo="${repo%.git}"
  mkdir -p "$HOME/Repos/$account"
  git clone "$url" "$HOME/Repos/$account/$repo" || return 1
  cd "$HOME/Repos/$account/$repo"
}

gclb() {
  local url="$1"
  local path="${url#git@github.com:}"
  path="${path#https://github.com/}"
  local account="${path%%/*}"
  local repo="${path##*/}"
  repo="${repo%.git}"
  mkdir -p "$HOME/Repos/$account"
  git clone "$url" "$HOME/Repos/$account/$repo"
}

sync_dots() {
  local msg="${1:-"Update dotfiles"}"
  pushd "$DOTFILES_DIR" >/dev/null || return 1
  brew bundle dump --force --file="Brewfile" >/dev/null 2>&1

  git add -A

  if ! git diff --cached --quiet; then
    git commit -q -m "$msg"
    git push -q -u origin main
    echo ""
    git --no-pager show --oneline --color HEAD
  fi
  popd >/dev/null || return 1
}

vois() {
  cd "$HOME/Repos/voisapp/backend" || return 1
  ruby -v
  git status -sb
  git fetch origin --quiet
}

ze() {
  local pre_hash
  pre_hash=$(cksum "$DOTFILES_DIR/.zshrc")
  $EDITOR "$DOTFILES_DIR/.zshrc"
  if [[ "$pre_hash" != "$(cksum "$DOTFILES_DIR/.zshrc")" ]]; then
    source "$DOTFILES_DIR/.zshrc"
    check_github_auth && sync_dots "Update .zshrc"
  fi
}

eval "$(fzf --zsh)"
