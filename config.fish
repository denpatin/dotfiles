set -gx DOTFILES_DIR "$HOME/dotfiles"
set -gx EDITOR nvim
set -gx LANG "en_US.UTF-8"
set -gx LC_ALL "en_US.UTF-8"

set -gx PATH "$HOME/.local/bin" $PATH

if test -d /opt/homebrew/opt/llvm
    set -gx PATH /opt/homebrew/opt/llvm/bin $PATH
    set -gx CC /opt/homebrew/opt/llvm/bin/clang
    set -gx CPPFLAGS "-I/opt/homebrew/opt/llvm/include $CPPFLAGS"
    set -gx CXX /opt/homebrew/opt/llvm/bin/clang++
    set -gx LDFLAGS "-L/opt/homebrew/opt/llvm/lib $LDFLAGS"
end

for ccache_dir in /opt/homebrew/opt/ccache/libexec /usr/lib/ccache/bin /usr/lib/ccache /usr/lib64/ccache
    if test -d $ccache_dir
        set -gx PATH $ccache_dir $PATH
        break
    end
end
set -e ccache_dir

if type -q sccache
    set -gx RUSTC_WRAPPER sccache
end

if test -x /opt/homebrew/bin/brew
    /opt/homebrew/bin/brew shellenv | source
end

alias cat="bat"
alias df="duf"
alias du="dust"
alias find="fd"
alias jq="jaq"
alias la="eza -lah --icons=auto --git"
alias ll="eza -lh --icons=auto --git"
alias ls="eza --icons=auto"
alias node="bun run"
alias npm="bun"
alias npx="bunx"
alias ps="procs"
alias tree="eza --tree --icons=auto"

if type -q ugrep
    alias grep="ugrep -G"
end

if type -q syswatch
    alias top="syswatch"
end

if type -q brew
    alias bs="brew search"
    alias upd="brew update && brew upgrade --cask --greedy && brew upgrade && brew autoremove && brew cleanup -s && brew doctor; mise upgrade; mise doctor | tail -n 1"
else if type -q apt-get
    alias upd="sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y; mise upgrade; mise doctor | tail -n 1"
else if type -q paru
    alias upd="paru -Syu; mise upgrade; mise doctor | tail -n 1"
else if type -q pacman
    alias upd="sudo pacman -Syu; mise upgrade; mise doctor | tail -n 1"
else if type -q dnf
    alias upd="sudo dnf upgrade -y && sudo dnf autoremove -y; mise upgrade; mise doctor | tail -n 1"
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

source ~/.orbstack/shell/init2.fish 2>/dev/null || :

if type -q broot
    source (broot --print-shell-function fish | psub)
end

if type -q pixi
    pixi completion --shell fish | source
end

zoxide init fish --cmd cd | source

if type -q starship
    starship init fish | source
end

mise activate fish | source

# Added by codebase-memory-mcp install
fish_add_path /Users/denpatin/.local/bin
