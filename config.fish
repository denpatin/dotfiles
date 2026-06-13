set -gx DOTFILES_DIR "$HOME/dotfiles"
set -gx EDITOR nvim
set -gx LANG "en_US.UTF-8"
set -gx LC_ALL "en_US.UTF-8"

fish_add_path --global "$HOME/.local/bin"

if test -x /opt/homebrew/bin/brew
    /opt/homebrew/bin/brew shellenv | source
end

mise activate fish | source
zoxide init fish --cmd cd | source

alias be="bundle exec"
alias cat="bat"
alias find="fd"
alias grep="rg"
alias la="eza -lah --icons=auto --git"
alias lg="lazygit"
alias ll="eza -lh --icons=auto --git"
alias ls="eza --icons=auto"
alias tree="eza --tree --icons=auto"
alias top="syswatch"

if type -q brew
    alias bs="brew search"
    alias upd="brew update && brew upgrade --cask --greedy && brew upgrade && brew autoremove && brew cleanup -s && brew doctor; mise upgrade; mise_elixir_pin; mise prune; mise doctor | tail -n 1"
else if type -q apt-get
    alias upd="sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get autoremove -y && mise upgrade; mise_elixir_pin"
else if type -q pacman
    alias upd="sudo pacman -Syu && mise upgrade; mise_elixir_pin"
end

if type -q brew
    function bi
        check_github_auth || return 1
        brew install $argv && sync_dots "Install "(string join " " $argv)
    end

    function bu
        check_github_auth || return 1
        brew uninstall $argv && sync_dots "Uninstall "(string join " " $argv)
    end
end

function mise_elixir_pin --description "Pin elixir to newest patch matching installed erlang OTP"
    type -q mise || return 0
    set -l cfg "$HOME/.config/mise/config.toml"
    test -f "$cfg" || return 0
    set -l cur (string match -r '^elixir = "([^"]+)"' < $cfg)[2]
    test -n "$cur" || return 0
    set -l parts (string split '.' $cur)
    set -l series "$parts[1].$parts[2]"
    set -l otp (string split '.' (mise current erlang 2>/dev/null))[1]
    test -n "$otp" || return 0
    set -l ver (mise ls-remote elixir | string match -r "^$series\.[0-9]+-otp-$otp\$" | tail -n 1)
    test -n "$ver" || return 0
    test "$ver" = "$cur" && return 0
    set -l content (string replace -r '^elixir = "[^"]+"' "elixir = \"$ver\"" < $cfg)
    printf '%s\n' $content >$cfg
    echo "elixir: $cur → $ver"
    mise install "elixir@$ver"
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

function fish_prompt
    set -l pwd (string replace -r '^'"$HOME" '~' (pwd))
    set -l split_path (string split '/' $pwd)
    if test (count $split_path) -gt 3
        if test "$split_path[1]" = "~"
            set pwd (string join '/' "~" ".." $split_path[-2] $split_path[-1])
        else
            set pwd (string join '/' ".." $split_path[-2] $split_path[-1])
        end
    end
    set_color cyan
    echo -n $pwd
    set_color normal
    if type -q fish_git_prompt
        set -g __fish_git_prompt_char_stateseparator ' '
        set_color magenta
        fish_git_prompt " (%s)"
    end
    set_color normal
    echo -n '> '
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

function mupd
    set -l repo "$HOME/Repos/denpatin/music"
    if not test -x "$repo/update.sh"
        echo "error: update.sh missing at $repo" >&2
        return 1
    end
    "$repo/update.sh"
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

if test -d /opt/homebrew/opt/llvm
    fish_add_path --prepend --global /opt/homebrew/opt/llvm/bin
    set -gx CC /opt/homebrew/opt/llvm/bin/clang
    set -gx CPPFLAGS "-I/opt/homebrew/opt/llvm/include $CPPFLAGS"
    set -gx CXX /opt/homebrew/opt/llvm/bin/clang++
    set -gx LDFLAGS "-L/opt/homebrew/opt/llvm/lib $LDFLAGS"
end

fish_add_path "$HOME/.local/bin"
