export DOTFILES_DIR="$HOME/dotfiles"
export EDITOR="nvim"
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME=""
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source "$ZSH/oh-my-zsh.sh"

if [[ -d /opt/homebrew/opt/llvm ]]; then
  export CC="/opt/homebrew/opt/llvm/bin/clang"
  export CPPFLAGS="-I/opt/homebrew/opt/llvm/include $CPPFLAGS"
  export CXX="/opt/homebrew/opt/llvm/bin/clang++"
  export LDFLAGS="-L/opt/homebrew/opt/llvm/lib $LDFLAGS"
  export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
elif command -v clang >/dev/null 2>&1; then
  export CC="clang"
  export CXX="clang++"
fi

for ccache_dir in /opt/homebrew/opt/ccache/libexec /usr/lib/ccache/bin /usr/lib/ccache /usr/lib64/ccache; do
  if [[ -d "$ccache_dir" ]]; then
    export PATH="$ccache_dir:$PATH"
    break
  fi
done
unset ccache_dir

if command -v ccache >/dev/null 2>&1; then
  export CCACHE_MAXSIZE=50G
  export CCACHE_COMPRESS=1
fi

if command -v sccache >/dev/null 2>&1; then
  export RUSTC_WRAPPER=sccache
  export SCCACHE_CACHE_SIZE=50G
fi

if [[ -r /etc/os-release ]] && grep -q '^ID=cachyos' /etc/os-release; then
  export CFLAGS="-march=native -mtune=native -O2 -pipe -fno-plt"
  export CXXFLAGS="$CFLAGS"
  export RUSTFLAGS="-C target-cpu=native"
  export GOAMD64=v3
  export MAKEFLAGS="-j$(nproc)"
  if command -v ninja >/dev/null 2>&1; then
    export CMAKE_GENERATOR=Ninja
  fi
fi

if [[ -d /ram/tmp ]]; then
  export TMPDIR=/ram/tmp
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

command -v bat >/dev/null 2>&1 && alias cat="bat"
command -v duf >/dev/null 2>&1 && alias df="duf"
command -v dust >/dev/null 2>&1 && alias du="dust"
command -v fd >/dev/null 2>&1 && alias find="fd"
command -v jaq >/dev/null 2>&1 && alias jq="jaq"

if command -v eza >/dev/null 2>&1; then
  alias la="eza -lah --icons=auto --git"
  alias ll="eza -lh --icons=auto --git"
  alias ls="eza --icons=auto"
  alias tree="eza --tree --icons=auto"
fi

if command -v bun >/dev/null 2>&1; then
  alias node="bun run"
  alias npm="bun"
  alias npx="bunx"
fi

command -v procs >/dev/null 2>&1 && alias ps="procs"
command -v ugrep >/dev/null 2>&1 && alias grep="ugrep -G"
command -v syswatch >/dev/null 2>&1 && alias top="syswatch"

if command -v brew >/dev/null 2>&1; then
  alias bs="brew search"
  alias upd="brew update && brew upgrade --cask --greedy && brew upgrade && brew autoremove && brew cleanup -s && brew doctor; mise upgrade; mise doctor | tail -n 1"
elif command -v paru >/dev/null 2>&1 || command -v apt-get >/dev/null 2>&1; then
  alias upd="upd_linux"
fi

upd_linux() {
  if command -v paru >/dev/null 2>&1; then
    echo "==> Updating system packages (repos + AUR)..."
    paru -Syu || return 1
  elif command -v apt-get >/dev/null 2>&1; then
    echo "==> Updating apt..."
    sudo apt-get update || return 1
    echo "==> Outdated packages"
    apt list --upgradable 2>/dev/null | tail -n +2
    sudo apt-get upgrade || return 1
    sudo apt-get autoremove
  fi

  if command -v mise >/dev/null 2>&1; then
    echo "==> Outdated mise tools"
    mise outdated
    mise upgrade
  fi

  if command -v uv >/dev/null 2>&1; then
    echo "==> Upgrading uv tools"
    uv tool upgrade --all
  fi

  if command -v mise >/dev/null 2>&1; then
    mise doctor | tail -n 1
  fi
}

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

ze() {
  local pre_hash
  pre_hash=$(cksum "$DOTFILES_DIR/.zshrc")
  $EDITOR "$DOTFILES_DIR/.zshrc"
  if [[ "$pre_hash" != "$(cksum "$DOTFILES_DIR/.zshrc")" ]]; then
    source "$DOTFILES_DIR/.zshrc"
    check_github_auth && sync_dots "Update .zshrc"
  fi
}

yy() {
  local tmp cwd
  tmp="$(mktemp -t yazi-cwd.XXXXXX)"
  yazi "$@" --cwd-file="$tmp"
  if cwd="$(command cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
    builtin cd -- "$cwd"
  fi
  rm -f -- "$tmp"
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

_ram_human() {
  local kb=$1
  if (( kb >= 1048576 )); then
    printf '%.1fG' "$(( kb / 1048576.0 ))"
  elif (( kb >= 1024 )); then
    printf '%.0fM' "$(( kb / 1024.0 ))"
  else
    printf '%dK' "$kb"
  fi
}

_ram_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)"
  [[ -z "$root" ]] && root="$PWD"
  printf '%s' "${root%/}"
}

_ram_check() {
  if [[ ! -d /ram/proj ]]; then
    echo "ram: /ram is not available (CachyOS only)" >&2
    return 1
  fi
  if ! mountpoint -q /ram; then
    echo "ram: /ram exists but is not a tmpfs mount" >&2
    return 1
  fi
  return 0
}

ram() {
  _ram_check || return 1

  local src name dst bak size_k free_k total_k need_k files
  src="$(_ram_root)"
  name="$(basename "$src")"
  dst="/ram/proj/$name"
  bak="$src.disk"

  if [[ -L "$src" ]]; then
    echo "==> ram: $name is already in RAM ($(realpath "$src"))"
    return 0
  fi
  if [[ ! -d "$src" ]]; then
    echo "ram: $src is not a directory" >&2
    return 1
  fi
  if [[ -e "$bak" ]]; then
    echo "ram: $bak already exists — resolve it manually first" >&2
    return 1
  fi
  if [[ -e "$dst" ]]; then
    echo "ram: $dst already exists — run 'unram' in the other checkout first" >&2
    return 1
  fi

  size_k=$(du -sk "$src" | cut -f1)
  free_k=$(df -Pk /ram | awk 'NR==2 {print $4}')
  total_k=$(df -Pk /ram | awk 'NR==2 {print $2}')
  need_k=$(( size_k + 2097152 ))

  echo "==> ram: $name ($(_ram_human "$size_k")) → $dst"

  if (( need_k > free_k )); then
    echo "    error: not enough space in /ram — need $(_ram_human "$need_k") (incl. 2G headroom), have $(_ram_human "$free_k")" >&2
    return 1
  fi
  echo "    checked: /ram mounted, $(_ram_human "$free_k") free of $(_ram_human "$total_k")"

  if ! rsync -a "$src/" "$dst/"; then
    echo "    error: rsync failed — rolling back" >&2
    rm -rf "$dst"
    return 1
  fi
  files=$(find "$dst" | wc -l | tr -d ' ')
  echo "    copied:  $files files, $(_ram_human "$size_k")"

  if ! mv "$src" "$bak"; then
    echo "    error: could not move $src aside — rolling back" >&2
    rm -rf "$dst"
    return 1
  fi
  if ! ln -s "$dst" "$src"; then
    echo "    error: could not create symlink — restoring $src" >&2
    mv "$bak" "$src"
    rm -rf "$dst"
    return 1
  fi

  echo "    linked:  $src → $dst"
  echo "    disk:    $bak (backing copy kept)"
  echo "==> done — work happens in RAM now; restart running processes (foreman, editors)"
  builtin cd "$src" || return 1
}

unram() {
  _ram_check || return 1

  local src name bak dst size_k files
  src="$(_ram_root)"
  name="$(basename "$src")"
  bak="$src.disk"

  if [[ ! -L "$src" ]]; then
    echo "ram: $name is not in RAM" >&2
    return 1
  fi

  dst="$(realpath "$src")"

  if [[ ! -d "$bak" ]]; then
    echo "ram: backing copy $bak is missing — refusing to touch the symlink" >&2
    return 1
  fi
  if [[ ! -d "$dst" ]]; then
    echo "==> unram: $name — RAM copy is gone (reboot?), restoring disk backing copy"
    rm -f "$src"
    mv "$bak" "$src"
    echo "==> done — restored $src from $bak"
    builtin cd "$src" || return 1
    return 0
  fi

  size_k=$(du -sk "$dst" | cut -f1)
  echo "==> unram: $name ($(_ram_human "$size_k")) → $bak"

  if ! rsync -a --delete "$dst/" "$bak/"; then
    echo "    error: rsync back failed — nothing changed, RAM copy is intact" >&2
    return 1
  fi
  files=$(find "$bak" | wc -l | tr -d ' ')
  echo "    synced:  $files files, $(_ram_human "$size_k") back to disk"

  rm -f "$src"
  if ! mv "$bak" "$src"; then
    echo "    error: could not restore $src from $bak" >&2
    return 1
  fi
  rm -rf "$dst"

  echo "    removed: $dst"
  echo "==> done — $name is back on disk; restart running processes (foreman, editors)"
  builtin cd "$src" || return 1
}

rams() {
  _ram_check || return 1

  local found=0 d size_k free_k total_k
  echo "==> projects in RAM (/ram/proj):"
  for d in /ram/proj/*; do
    [[ -d "$d" ]] || continue
    found=1
    size_k=$(du -sk "$d" | cut -f1)
    printf '  %-24s %8s\n' "$(basename "$d")" "$(_ram_human "$size_k")"
  done
  if (( found == 0 )); then
    echo "  (none)"
  fi
  free_k=$(df -Pk /ram | awk 'NR==2 {print $4}')
  total_k=$(df -Pk /ram | awk 'NR==2 {print $2}')
  echo "    $(_ram_human "$free_k") free of $(_ram_human "$total_k")"
}

source "$HOME/.orbstack/shell/init.zsh" 2>/dev/null || :

if command -v broot >/dev/null 2>&1; then
  source <(broot --print-shell-function zsh)
fi

if command -v pixi >/dev/null 2>&1; then
  eval "$(pixi completion --shell zsh)"
fi

if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --zsh)"
fi

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh --cmd cd)"
fi

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi

export PATH="/Users/denpatin/.local/bin:$PATH"
