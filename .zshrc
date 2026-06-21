export DOTFILES_DIR="$HOME/dotfiles"
export EDITOR="nvim"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export PATH="$HOME/.local/bin:$PATH"
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="robbyrussell"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source "$ZSH/oh-my-zsh.sh"

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

eval "$(mise activate zsh)"
eval "$(zoxide init zsh --cmd cd)"

if command -v rv >/dev/null 2>&1; then
  eval "$(rv shell init zsh)"
fi

alias cat="bat"
alias df="duf"
alias du="dust"
alias find="fd"
alias grep="rg"
alias la="eza -lah --icons=auto --git"
alias ll="eza -lh --icons=auto --git"
alias ls="eza --icons=auto"
alias ps="procs"
alias tree="eza --tree --icons=auto"
command -v syswatch >/dev/null 2>&1 && alias top="syswatch"

if command -v brew >/dev/null 2>&1; then
  alias bs="brew search"
  alias upd="brew update && brew upgrade --cask --greedy && brew upgrade && brew autoremove && brew cleanup -s && brew doctor; mise upgrade; mise_elixir_pin; mise doctor | tail -n 1"
elif command -v apt-get >/dev/null 2>&1; then
  alias upd="sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y; mise upgrade; mise_elixir_pin; mise doctor | tail -n 1"
elif command -v paru >/dev/null 2>&1; then
  alias upd="paru -Syu; mise upgrade; mise_elixir_pin; mise doctor | tail -n 1"
elif command -v pacman >/dev/null 2>&1; then
  alias upd="sudo pacman -Syu; mise upgrade; mise_elixir_pin; mise doctor | tail -n 1"
elif command -v dnf >/dev/null 2>&1; then
  alias upd="sudo dnf upgrade -y && sudo dnf autoremove -y; mise upgrade; mise_elixir_pin; mise doctor | tail -n 1"
fi

if command -v brew >/dev/null 2>&1; then
  bi() {
    check_github_auth || return 1
    brew update &>/dev/null && brew install "$@" && sync_dots "Install $*"
  }

  bu() {
    check_github_auth || return 1
    brew uninstall "$@" && sync_dots "Uninstall $*"
  }
fi

mise_elixir_pin() {
  command -v mise >/dev/null 2>&1 || return 0
  local cfg="$HOME/.config/mise/config.toml"
  [[ -f "$cfg" ]] || return 0
  local cur
  cur=$(sed -n 's/^elixir = "\([^"]*\)".*/\1/p' "$cfg")
  [[ -n "$cur" ]] || return 0
  local rest="${cur#*.}"
  local series="${cur%%.*}.${rest%%.*}"
  local otp
  otp=$(mise current erlang 2>/dev/null)
  otp="${otp%%.*}"
  [[ -n "$otp" ]] || return 0
  local ver
  ver=$(mise ls-remote elixir | grep -E "^${series}\.[0-9]+-otp-${otp}\$" | tail -n 1)
  [[ -n "$ver" ]] || return 0
  [[ "$ver" == "$cur" ]] && return 0
  sed -i.bak "s/^elixir = \"[^\"]*\"/elixir = \"$ver\"/" "$cfg" && rm -f "$cfg.bak"
  echo "elixir: $cur → $ver"
  mise install "elixir@$ver"
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

unalias gcl 2>/dev/null
unalias gclb 2>/dev/null

gcl() {
  local url="$1"
  local path="${url#git@github.com:}"
  path="${path#https://github.com/}"
  local account="${path%%/*}"
  local repo="${path##*/}"
  repo="${repo%.git}"
  mkdir -p "$HOME/Repos/$account"
  git clone "$url" "$HOME/Repos/$account/$repo" || return 1
  cd "$HOME/Repos/$account/$repo" || return 2
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

mupd() {
  local repo="$HOME/Repos/denpatin/music"
  if [[ ! -x "$repo/update.sh" ]]; then
    echo "error: update.sh missing at $repo" >&2
    return 1
  fi
  "$repo/update.sh"
}

sync_dots() {
  local msg="${1:-"Update dotfiles"}"
  pushd "$DOTFILES_DIR" >/dev/null || return 1
  if command -v brew >/dev/null 2>&1; then
    brew bundle dump --force --file="Brewfile" >/dev/null 2>&1
  fi

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

source "$HOME/.orbstack/shell/init.zsh" 2>/dev/null || :

if [[ -d /opt/homebrew/opt/llvm ]]; then
  export CC="/opt/homebrew/opt/llvm/bin/clang"
  export CPPFLAGS="-I/opt/homebrew/opt/llvm/include $CPPFLAGS"
  export CXX="/opt/homebrew/opt/llvm/bin/clang++"
  export LDFLAGS="-L/opt/homebrew/opt/llvm/lib $LDFLAGS"
  export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
fi

for ccache_dir in /opt/homebrew/opt/ccache/libexec /usr/lib/ccache/bin /usr/lib/ccache /usr/lib64/ccache; do
  if [[ -d "$ccache_dir" ]]; then
    export PATH="$ccache_dir:$PATH"
    break
  fi
done
unset ccache_dir

if command -v sccache >/dev/null 2>&1; then
  export RUSTC_WRAPPER=sccache
fi
