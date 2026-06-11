#!/usr/bin/env bash
set -euo pipefail

DOTFILES_DIR="$HOME/dotfiles"
OS=""
ARCH=""
WSL=0
SHELL_CHOICE=""
UBUNTU_VERSION=""
MISE_BIN="mise"

log() { printf '%s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

detect_platform() {
  local kernel machine
  kernel="$(uname -s)"
  machine="$(uname -m)"
  case "$machine" in
    arm64 | aarch64) ARCH=arm64 ;;
    x86_64 | amd64) ARCH=x86_64 ;;
    *) die "untested architecture: $machine" ;;
  esac
  case "$kernel" in
    Darwin)
      [ "$ARCH" = arm64 ] || die "untested platform: macOS on $machine"
      OS=macos
      ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        WSL=1
      fi
      [ -r /etc/os-release ] || die "untested platform: unidentified Linux"
      . /etc/os-release
      case "$ID" in
        ubuntu)
          OS=ubuntu
          UBUNTU_VERSION="${VERSION_ID:-}"
          ;;
        arch) OS=arch ;;
        *) die "untested platform: $ID" ;;
      esac
      ;;
    *) die "untested platform: $kernel" ;;
  esac
  if [ "$WSL" -eq 1 ]; then
    log "platform: $OS $ARCH (wsl2)"
  else
    log "platform: $OS $ARCH"
  fi
}

choose_shell() {
  local answer
  printf 'shell to configure [zsh/fish]: '
  read -r answer
  case "$answer" in
    zsh | fish) SHELL_CHOICE="$answer" ;;
    *) die "invalid shell: $answer" ;;
  esac
}

install_homebrew() {
  if ! command -v brew >/dev/null 2>&1; then
    log "installing homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  eval "$(/opt/homebrew/bin/brew shellenv)"
}

install_macos() {
  install_homebrew
  log "running brew bundle..."
  if ! brew bundle --file="$DOTFILES_DIR/Brewfile"; then
    warn "brew bundle finished with errors, rerun 'brew bundle' later"
  fi
}

apt_install() {
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

install_vscode_ubuntu() {
  if command -v code >/dev/null 2>&1; then
    return 0
  fi
  log "installing vscode..."
  curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
    | sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
  echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
    | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
  sudo apt-get update
  apt_install code
}

install_ngrok_ubuntu() {
  if command -v ngrok >/dev/null 2>&1; then
    return 0
  fi
  log "installing ngrok..."
  curl -fsSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
    | sudo gpg --dearmor -o /usr/share/keyrings/ngrok.gpg
  echo "deb [signed-by=/usr/share/keyrings/ngrok.gpg] https://ngrok-agent.s3.amazonaws.com bookworm main" \
    | sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null
  sudo apt-get update
  apt_install ngrok
}

install_awscli_linux() {
  if command -v aws >/dev/null 2>&1; then
    return 0
  fi
  log "installing awscli..."
  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "$tmp/awscliv2.zip"
  unzip -q "$tmp/awscliv2.zip" -d "$tmp"
  sudo "$tmp/aws/install" --update
  rm -rf "$tmp"
}

install_postgres_ubuntu() {
  if command -v psql >/dev/null 2>&1; then
    return 0
  fi
  log "installing postgresql..."
  apt_install postgresql-common
  sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
  sudo apt-get update
  apt_install postgresql
}

install_ghostty_ubuntu() {
  if command -v ghostty >/dev/null 2>&1; then
    return 0
  fi
  log "installing ghostty..."
  local deb_arch url tmp
  case "$ARCH" in
    arm64) deb_arch=arm64 ;;
    x86_64) deb_arch=amd64 ;;
  esac
  url="$(curl -fsSL https://api.github.com/repos/mkasberg/ghostty-ubuntu/releases/latest \
    | grep -o "https://[^\"]*_${deb_arch}_${UBUNTU_VERSION}\.deb" | head -n1)"
  if [ -z "$url" ]; then
    warn "no ghostty build for ubuntu $UBUNTU_VERSION $deb_arch, skipping"
    return 0
  fi
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/ghostty.deb"
  apt_install "$tmp/ghostty.deb"
  rm -rf "$tmp"
}

install_nerd_font_ubuntu() {
  if fc-list 2>/dev/null | grep -q "JetBrainsMono Nerd Font"; then
    return 0
  fi
  log "installing jetbrainsmono nerd font..."
  local font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerd"
  mkdir -p "$font_dir"
  curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip \
    -o /tmp/JetBrainsMono.zip
  unzip -o -q /tmp/JetBrainsMono.zip -d "$font_dir"
  rm -f /tmp/JetBrainsMono.zip
  fc-cache -f
}

install_ubuntu() {
  log "updating apt..."
  sudo apt-get update
  log "installing base packages..."
  apt_install \
    build-essential clang clang-format clang-tools lld llvm gdb cmake pkg-config \
    git curl wget ca-certificates gnupg unzip zip tree software-properties-common \
    locales fontconfig fonts-jetbrains-mono \
    autoconf automake libtool m4 libssl-dev libncurses-dev libreadline-dev \
    libyaml-dev zlib1g-dev libffi-dev \
    texlive-latex-extra texlive-fonts-extra texlive-xetex texlive-luatex \
    latexmk biber chktex
  sudo locale-gen en_US.UTF-8
  if [ "$SHELL_CHOICE" = fish ]; then
    log "installing fish..."
    sudo add-apt-repository -y ppa:fish-shell/release-4
    sudo apt-get update
    apt_install fish
  else
    log "installing zsh..."
    apt_install zsh
  fi
  install_vscode_ubuntu
  install_ghostty_ubuntu
  install_nerd_font_ubuntu
  install_ngrok_ubuntu
  install_awscli_linux
  install_postgres_ubuntu
}

aur_install() {
  local pkg="$1" tmp
  if pacman -Qi "$pkg" >/dev/null 2>&1; then
    return 0
  fi
  log "installing $pkg from aur..."
  tmp="$(mktemp -d)"
  git clone -q "https://aur.archlinux.org/$pkg.git" "$tmp"
  (cd "$tmp" && makepkg -si --noconfirm)
  rm -rf "$tmp"
}

init_postgres_arch() {
  if sudo test ! -f /var/lib/postgres/data/PG_VERSION; then
    log "initializing postgresql cluster..."
    sudo -u postgres initdb --locale=en_US.UTF-8 -D /var/lib/postgres/data
  fi
  if command -v systemctl >/dev/null 2>&1 && pidof systemd >/dev/null 2>&1; then
    sudo systemctl enable --now postgresql
  else
    warn "systemd not running, start postgresql manually"
  fi
}

install_arch() {
  log "updating pacman..."
  sudo pacman -Syu --noconfirm
  log "installing base packages..."
  sudo pacman -S --needed --noconfirm \
    base-devel clang llvm lld gcc gdb cmake pkgconf \
    git curl wget unzip zip tree \
    openssl ncurses readline libyaml zlib libffi \
    fontconfig ttf-jetbrains-mono ttf-jetbrains-mono-nerd \
    texlive-basic texlive-latex texlive-latexextra texlive-fontsextra \
    texlive-binextra texlive-xetex texlive-luatex biber \
    postgresql aws-cli ghostty
  if [ "$SHELL_CHOICE" = fish ]; then
    sudo pacman -S --needed --noconfirm fish
  else
    sudo pacman -S --needed --noconfirm zsh
  fi
  if ! grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen; then
    sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    sudo locale-gen
  fi
  aur_install visual-studio-code-bin
  aur_install ngrok
  install_awscli_linux
  init_postgres_arch
}

install_mise_linux() {
  if ! command -v mise >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/mise" ]; then
    log "installing mise..."
    curl -fsSL https://mise.run | sh
  fi
  MISE_BIN="$HOME/.local/bin/mise"
}

install_oh_my_zsh() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log "installing oh-my-zsh..."
    RUNZSH=no CHSH=no /bin/sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi
  local zsh_custom="$HOME/.oh-my-zsh/custom"
  if [ ! -d "$zsh_custom/plugins/zsh-autosuggestions" ]; then
    git clone -q https://github.com/zsh-users/zsh-autosuggestions "$zsh_custom/plugins/zsh-autosuggestions"
  fi
  if [ ! -d "$zsh_custom/plugins/zsh-syntax-highlighting" ]; then
    git clone -q https://github.com/zsh-users/zsh-syntax-highlighting "$zsh_custom/plugins/zsh-syntax-highlighting"
  fi
}

link_dotfiles() {
  log "symlinking dotfiles..."
  ln -sf "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"

  mkdir -p "$HOME/.config/mise"
  ln -sf "$DOTFILES_DIR/mise/config.toml" "$HOME/.config/mise/config.toml"
  if [ "$OS" != macos ]; then
    mkdir -p "$HOME/.config/mise/conf.d"
    ln -sf "$DOTFILES_DIR/mise/linux.toml" "$HOME/.config/mise/conf.d/linux.toml"
  fi

  mkdir -p "$HOME/.config"
  ln -sfn "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
  ln -sfn "$DOTFILES_DIR/ghostty" "$HOME/.config/ghostty"

  mkdir -p "$HOME/.ssh"
  ln -sf "$DOTFILES_DIR/ssh/config" "$HOME/.ssh/config"
  chmod 700 "$HOME/.ssh"
  chmod 600 "$DOTFILES_DIR/ssh/config"

  if [ "$SHELL_CHOICE" = fish ]; then
    mkdir -p "$HOME/.config/fish/functions"
    ln -sf "$DOTFILES_DIR/config.fish" "$HOME/.config/fish/config.fish"
    ln -sf "$DOTFILES_DIR/fish_functions/fish_user_key_bindings.fish" "$HOME/.config/fish/functions/fish_user_key_bindings.fish"
  else
    ln -sf "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
    ln -sf "$DOTFILES_DIR/.zshenv" "$HOME/.zshenv"
  fi

  local vscode_user_dir
  if [ "$OS" = macos ]; then
    vscode_user_dir="$HOME/Library/Application Support/Code/User"
  else
    vscode_user_dir="$HOME/.config/Code/User"
  fi
  mkdir -p "$vscode_user_dir"
  ln -sf "$DOTFILES_DIR/vscode/settings.json" "$vscode_user_dir/settings.json"
}

install_languages() {
  log "installing mise tools..."
  if ! MISE_YES=1 "$MISE_BIN" install; then
    warn "some mise tools failed to install, rerun 'mise install' later"
  fi
}

install_python_tools() {
  log "installing python tooling..."
  local uv_bin
  uv_bin="$("$MISE_BIN" which uv 2>/dev/null || command -v uv || true)"
  if [ -z "$uv_bin" ]; then
    warn "uv not found, skipping jupyterlab"
    return 0
  fi
  "$uv_bin" tool install --upgrade jupyterlab
}

install_vscode_extensions() {
  if ! command -v code >/dev/null 2>&1; then
    warn "code not found, skipping vscode extensions"
    return 0
  fi
  log "installing vscode extensions..."
  grep '^vscode "' "$DOTFILES_DIR/Brewfile" | cut -d'"' -f2 | while read -r ext; do
    code --install-extension "$ext" --force >/dev/null 2>&1 || warn "failed: $ext"
  done
}

current_login_shell() {
  if [ "$OS" = macos ]; then
    dscl . -read "/Users/$USER" UserShell | awk '{print $2}'
  else
    getent passwd "$USER" | cut -d: -f7
  fi
}

set_default_shell() {
  local shell_path current
  shell_path="$(command -v "$SHELL_CHOICE")"
  [ -n "$shell_path" ] || die "$SHELL_CHOICE not found on PATH"
  if ! grep -qF "$shell_path" /etc/shells 2>/dev/null; then
    log "registering $shell_path in /etc/shells..."
    echo "$shell_path" | sudo tee -a /etc/shells >/dev/null
  fi
  current="$(current_login_shell)"
  if [ "$current" = "$shell_path" ]; then
    log "default shell already $shell_path"
    return 0
  fi
  log "setting default shell to $shell_path..."
  if [ "$OS" = macos ]; then
    chsh -s "$shell_path" || warn "chsh failed, run: chsh -s $shell_path"
  else
    sudo chsh -s "$shell_path" "$USER" || warn "chsh failed, run: sudo chsh -s $shell_path $USER"
  fi
}

main() {
  [ "$(id -u)" -ne 0 ] || die "do not run as root"
  log "bootstrapping system..."
  detect_platform
  choose_shell
  mkdir -p "$HOME/Repos"
  case "$OS" in
    macos) install_macos ;;
    ubuntu) install_ubuntu ;;
    arch) install_arch ;;
  esac
  if [ "$SHELL_CHOICE" = zsh ]; then
    install_oh_my_zsh
  fi
  link_dotfiles
  if [ "$OS" != macos ]; then
    install_mise_linux
  fi
  install_languages
  install_python_tools
  if [ "$OS" != macos ]; then
    install_vscode_extensions
  fi
  set_default_shell
  log "system ready."
  if [ "$(current_login_shell)" != "${SHELL:-}" ]; then
    log "note: open a new terminal session to use $SHELL_CHOICE"
  fi
}

main "$@"
