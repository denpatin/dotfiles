set -gx DOTFILES_DIR "$HOME/dotfiles"
set -gx EDITOR nvim
set -gx LANG "en_US.UTF-8"
set -gx LC_ALL "en_US.UTF-8"

fish_add_path "$HOME/.local/bin"
fish_add_path "$HOME/.bun/bin"

if test -d /opt/homebrew/opt/llvm
    set -gx PATH /opt/homebrew/opt/llvm/bin $PATH
    set -gx CC /opt/homebrew/opt/llvm/bin/clang
    set -gx CPPFLAGS "-I/opt/homebrew/opt/llvm/include $CPPFLAGS"
    set -gx CXX /opt/homebrew/opt/llvm/bin/clang++
    set -gx LDFLAGS "-L/opt/homebrew/opt/llvm/lib $LDFLAGS"
else if type -q clang
    set -gx CC clang
    set -gx CXX clang++
end

for ccache_dir in /opt/homebrew/opt/ccache/libexec /usr/lib/ccache/bin /usr/lib/ccache /usr/lib64/ccache
    if test -d $ccache_dir
        set -gx PATH $ccache_dir $PATH
        break
    end
end
set -e ccache_dir

if type -q ccache
    set -gx CCACHE_MAXSIZE 50G
    set -gx CCACHE_COMPRESS 1
end

if type -q sccache
    set -gx RUSTC_WRAPPER sccache
    set -gx SCCACHE_CACHE_SIZE 50G
end

if test -r /etc/os-release; and grep -q '^ID=cachyos' /etc/os-release
    set -gx CFLAGS "-march=native -mtune=native -O2 -pipe -fno-plt"
    set -gx CXXFLAGS "$CFLAGS"
    set -gx RUSTFLAGS "-C target-cpu=native"
    set -gx GOAMD64 v3
    set -gx MAKEFLAGS "-j"(nproc)
    if type -q ninja
        set -gx CMAKE_GENERATOR Ninja
    end
end

if test -d /ram/tmp
    set -gx TMPDIR /ram/tmp
end

if test -x /opt/homebrew/bin/brew
    /opt/homebrew/bin/brew shellenv | source
end

if type -q bat
    alias cat="bat"
end

if type -q duf
    alias df="duf"
end

if type -q dust
    alias du="dust"
end

if type -q fd
    alias find="fd"
end

if type -q jaq
    alias jq="jaq"
end

if type -q eza
    alias la="eza -lah --icons=auto --git"
    alias ll="eza -lh --icons=auto --git"
    alias ls="eza --icons=auto"
    alias tree="eza --tree --icons=auto"
end

if type -q bun
    alias node="bun run"
    alias npm="bun"
    alias npx="bunx"
end

if type -q procs
    alias ps="procs"
end

if type -q ugrep
    alias grep="ugrep -G"
end

if type -q syswatch
    alias top="syswatch"
end

if type -q brew
    alias bs="brew search"
    alias upd="brew update && brew upgrade --cask --greedy && brew upgrade && brew autoremove && brew cleanup -s && brew doctor; mise upgrade; mise doctor | tail -n 1"
else if type -q paru
    alias upd="upd_linux"
else if type -q apt-get
    alias upd="upd_linux"
end

function upd_linux
    if type -q paru
        echo "==> Updating system packages (repos + AUR)..."
        paru -Syu; or return 1
    else if type -q apt-get
        echo "==> Updating apt..."
        sudo apt-get update; or return 1
        echo "==> Outdated packages"
        apt list --upgradable 2>/dev/null | tail -n +2
        sudo apt-get upgrade; or return 1
        sudo apt-get autoremove
    end

    if type -q mise
        echo "==> Outdated mise tools"
        mise outdated
        mise upgrade
    end

    if type -q uv
        echo "==> Upgrading uv tools"
        uv tool upgrade --all
    end

    if type -q mise
        mise doctor | tail -n 1
    end
end

if type -q brew
    function bi
        check_github_auth || return 1
        brew update &>/dev/null && brew install $argv && sync_dots "Install "(string join " " $argv)
    end

    function bu
        check_github_auth || return 1
        brew uninstall $argv && sync_dots "Uninstall "(string join " " $argv)
    end
end

function check_github_auth
    if not test -f "$HOME/.ssh/id_ed25519"
        echo "error: ssh key missing at ~/.ssh/id_ed25519" >&2
        return 1
    end
    if not ssh -q -o BatchMode=yes -T git@github.com 2>&1 | grep -q "successfully authenticated"
        echo "error: github authentication failed" >&2
        return 1
    end
    return 0
end

function fe
    set -l pre_hash (cksum "$DOTFILES_DIR/config.fish")
    $EDITOR "$DOTFILES_DIR/config.fish"
    if test "$pre_hash" != (cksum "$DOTFILES_DIR/config.fish")
        source "$DOTFILES_DIR/config.fish"
        check_github_auth && sync_dots "Update config.fish"
    end
end

function yy
    set -l tmp (mktemp -t yazi-cwd.XXXXXX)
    yazi $argv --cwd-file="$tmp"
    if test -f "$tmp"
        set -l cwd (command cat -- "$tmp")
        if test -n "$cwd"; and test "$cwd" != "$PWD"
            builtin cd -- "$cwd"
        end
    end
    rm -f -- "$tmp"
end

function gcl
    set -l url $argv[1]
    set -l path (string replace -r '^git@github\.com:' '' (string replace -r '^https://github\.com/' '' $url))
    set -l parts (string split '/' $path)
    set -l account $parts[1]
    set -l repo (string replace -r '\.git$' '' $parts[2])
    mkdir -p "$HOME/Repos/$account"
    git clone $url "$HOME/Repos/$account/$repo" || return 1
    cd "$HOME/Repos/$account/$repo"
end

function gclb
    set -l url $argv[1]
    set -l path (string replace -r '^git@github\.com:' '' (string replace -r '^https://github\.com/' '' $url))
    set -l parts (string split '/' $path)
    set -l account $parts[1]
    set -l repo (string replace -r '\.git$' '' $parts[2])
    mkdir -p "$HOME/Repos/$account"
    git clone $url "$HOME/Repos/$account/$repo"
end

function sync_dots
    set -l msg $argv[1]
    if test -z "$msg"
        set msg "Update dotfiles"
    end
    pushd "$DOTFILES_DIR" >/dev/null || return 1
    if type -q brew
        brew bundle dump --force --file="Brewfile" >/dev/null 2>&1
    end

    git add -A

    if not git diff --cached --quiet
        git commit -q -m "$msg"
        git push -q -u origin main
        echo ""
        git --no-pager show --oneline --color HEAD
    end
    popd >/dev/null || return 1
end

function vois
    cd "$HOME/Repos/voisapp/backend" || return 1
    ruby -v
    git status -sb
    git fetch origin --quiet
end

function _ram_human
    set -l kb $argv[1]
    if test $kb -ge 1048576
        printf '%.1fG' (math "$kb / 1048576")
    else if test $kb -ge 1024
        printf '%.0fM' (math "$kb / 1024")
    else
        printf '%dK' $kb
    end
end

function _ram_root
    set -l root (git rev-parse --show-toplevel 2>/dev/null)
    if test -z "$root"
        set root "$PWD"
    end
    printf '%s' (string replace -r '/$' '' $root)
end

function _ram_check
    if not test -d /ram/proj
        echo "ram: /ram is not available (CachyOS only)" >&2
        return 1
    end
    if not mountpoint -q /ram
        echo "ram: /ram exists but is not a tmpfs mount" >&2
        return 1
    end
    return 0
end

function ram
    _ram_check; or return 1

    set -l src (_ram_root)
    set -l name (basename "$src")
    set -l dst "/ram/proj/$name"
    set -l bak "$src.disk"

    if test -L "$src"
        echo "==> ram: $name is already in RAM ("(realpath "$src")")"
        return 0
    end
    if not test -d "$src"
        echo "ram: $src is not a directory" >&2
        return 1
    end
    if test -e "$bak"
        echo "ram: $bak already exists — resolve it manually first" >&2
        return 1
    end
    if test -e "$dst"
        echo "ram: $dst already exists — run 'unram' in the other checkout first" >&2
        return 1
    end

    set -l size_k (du -sk "$src" | cut -f1)
    set -l free_k (df -Pk /ram | awk 'NR==2 {print $4}')
    set -l total_k (df -Pk /ram | awk 'NR==2 {print $2}')
    set -l need_k (math "$size_k + 2097152")

    echo "==> ram: $name ("(_ram_human $size_k)") → $dst"

    if test $need_k -gt $free_k
        echo "    error: not enough space in /ram — need "(_ram_human $need_k)" (incl. 2G headroom), have "(_ram_human $free_k) >&2
        return 1
    end
    echo "    checked: /ram mounted, "(_ram_human $free_k)" free of "(_ram_human $total_k)

    if not rsync -a --info=stats2 "$src/" "$dst/" >/dev/null
        echo "    error: rsync failed — rolling back" >&2
        rm -rf "$dst"
        return 1
    end
    set -l files (find "$dst" | wc -l | string trim)
    echo "    copied:  $files files, "(_ram_human $size_k)

    if not mv "$src" "$bak"
        echo "    error: could not move $src aside — rolling back" >&2
        rm -rf "$dst"
        return 1
    end
    if not ln -s "$dst" "$src"
        echo "    error: could not create symlink — restoring $src" >&2
        mv "$bak" "$src"
        rm -rf "$dst"
        return 1
    end

    echo "    linked:  $src → $dst"
    echo "    disk:    $bak (backing copy kept)"
    echo "==> done — work happens in RAM now; restart running processes (foreman, editors)"
    builtin cd "$src"
end

function unram
    _ram_check; or return 1

    set -l src (_ram_root)
    set -l name (basename "$src")
    set -l bak "$src.disk"

    if not test -L "$src"
        echo "ram: $name is not in RAM" >&2
        return 1
    end

    set -l dst (realpath "$src")

    if not test -d "$bak"
        echo "ram: backing copy $bak is missing — refusing to touch the symlink" >&2
        return 1
    end
    if not test -d "$dst"
        echo "==> unram: $name — RAM copy is gone (reboot?), restoring disk backing copy"
        rm -f "$src"
        mv "$bak" "$src"
        echo "==> done — restored $src from $bak"
        builtin cd "$src"
        return 0
    end

    set -l size_k (du -sk "$dst" | cut -f1)
    echo "==> unram: $name ("(_ram_human $size_k)") → $bak"

    if not rsync -a --delete --info=stats2 "$dst/" "$bak/" >/dev/null
        echo "    error: rsync back failed — nothing changed, RAM copy is intact" >&2
        return 1
    end
    set -l files (find "$bak" | wc -l | string trim)
    echo "    synced:  $files files, "(_ram_human $size_k)" back to disk"

    rm -f "$src"
    if not mv "$bak" "$src"
        echo "    error: could not restore $src from $bak" >&2
        return 1
    end
    rm -rf "$dst"

    echo "    removed: $dst"
    echo "==> done — $name is back on disk; restart running processes (foreman, editors)"
    builtin cd "$src"
end

function rams
    _ram_check; or return 1

    set -l found 0
    echo "==> projects in RAM (/ram/proj):"
    for d in /ram/proj/*
        test -d "$d"; or continue
        set found 1
        set -l size_k (du -sk "$d" | cut -f1)
        printf '  %-24s %8s\n' (basename "$d") (_ram_human $size_k)
    end
    if test $found -eq 0
        echo "  (none)"
    end
    set -l free_k (df -Pk /ram | awk 'NR==2 {print $4}')
    set -l total_k (df -Pk /ram | awk 'NR==2 {print $2}')
    echo "    "(_ram_human $free_k)" free of "(_ram_human $total_k)
end

source ~/.orbstack/shell/init2.fish 2>/dev/null || :

if type -q broot
    source (broot --print-shell-function fish | psub)
end

if type -q pixi
    pixi completion --shell fish | source
end

if type -q zoxide
    zoxide init fish --cmd cd | source
end

if type -q starship
    starship init fish | source
end

if type -q mise
    mise activate fish | source
end
