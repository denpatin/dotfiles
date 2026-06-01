#!/usr/bin/env bash
set -euo pipefail

echo "bootstrapping system..."

DOTFILES_DIR="$HOME/dotfiles"

echo -n "checking homebrew... "
if ! command -v brew >/dev/null 2>&1; then
  echo "missing"
  echo "installing homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  eval "$(/opt/homebrew/bin/brew shellenv)"
else
  echo "ok"
fi

echo -n "checking zsh... "
if ! command -v zsh >/dev/null 2>&1; then
  echo "missing"
  echo "installing zsh..."
  brew install zsh
else
  echo "ok"
fi

echo -n "checking oh-my-zsh... "
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "missing"
  echo "installing oh-my-zsh..."
  RUNZSH=no CHSH=no /bin/sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "ok"
fi

echo "checking zsh plugins..."
ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
  git clone -q https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
  git clone -q https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

echo "symlinking dotfiles..."
ln -sf "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
ln -sf "$DOTFILES_DIR/.zshenv" "$HOME/.zshenv"
ln -sf "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"

mkdir -p "$HOME/.config/mise"
ln -sf "$DOTFILES_DIR/mise/config.toml" "$HOME/.config/mise/config.toml"

mkdir -p "$HOME/.config"
ln -sfn "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
ln -sfn "$DOTFILES_DIR/ghostty" "$HOME/.config/ghostty"

mkdir -p "$HOME/.ssh"
ln -sf "$DOTFILES_DIR/ssh/config" "$HOME/.ssh/config"
chmod 700 "$HOME/.ssh"
chmod 600 "$HOME/.ssh/config"

mkdir -p "$HOME/.config/fish/functions"
ln -sf "$DOTFILES_DIR/config.fish" "$HOME/.config/fish/config.fish"
ln -sf "$DOTFILES_DIR/fish_functions/fish_user_key_bindings.fish" "$HOME/.config/fish/functions/fish_user_key_bindings.fish"

mkdir -p "$HOME/Library/Application Support/Code/User"
ln -sf "$DOTFILES_DIR/vscode/settings.json" "$HOME/Library/Application Support/Code/User/settings.json"

echo "running brew bundle..."
brew bundle --file="$DOTFILES_DIR/Brewfile"

echo "installing mise tools..."
eval "$(/opt/homebrew/bin/brew shellenv)"
mise install

echo -n "checking fish shell registration... "
FISH_PATH="$(command -v fish)"
if ! grep -qF "$FISH_PATH" /etc/shells 2>/dev/null; then
  echo "registering..."
  echo "$FISH_PATH" | sudo tee -a /etc/shells
else
  echo "ok"
fi
if [ "$SHELL" != "$FISH_PATH" ]; then
  echo "setting fish as default shell..."
  chsh -s "$FISH_PATH"
fi

echo "system ready."
