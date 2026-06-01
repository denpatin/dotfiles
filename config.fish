set -gx DOTFILES_DIR "$HOME/dotfiles"
set -gx EDITOR nvim
set -gx LANG "en_US.UTF-8"
set -gx LC_ALL "en_US.UTF-8"

/opt/homebrew/bin/brew shellenv | source
mise activate fish | source
zoxide init fish --cmd cd | source

alias be="bundle exec"
alias bs="brew search"
alias cat="bat"
alias find="fd"
alias gph="git push heroku main"
alias grep="rg"
alias la="eza -lah --icons=auto --git"
alias lg="lazygit"
alias ll="eza -lh --icons=auto --git"
alias ls="eza --icons=auto"
alias tree="eza --tree --icons=auto"
alias upd="brew update && brew upgrade --cask --greedy && brew upgrade && brew autoremove && brew cleanup && brew doctor"

function bi
    check_github_auth || return 1
    brew install $argv && sync_dots "Install "(string join " " $argv)
end

function bu
    check_github_auth || return 1
    brew uninstall $argv && sync_dots "Uninstall "(string join " " $argv)
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

function sync_dots
    set -l msg $argv[1]
    if test -z "$msg"
        set msg "Update dotfiles"
    end
    pushd "$DOTFILES_DIR" >/dev/null || return 1
    brew bundle dump --force --file="Brewfile" >/dev/null 2>&1

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
    mise install
    ruby -v
    git status -sb
    git fetch origin --quiet
end
