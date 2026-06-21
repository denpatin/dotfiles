#!/usr/bin/env bash
set -euo pipefail


DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
OS=""
ARCH=""
WSL=0
SHELL_CHOICE=""
UBUNTU_VERSION=""
UBUNTU_CODENAME=""
DISTRO_FAMILY=""
PKG=""
AUR_HELPER=""
MISE_BIN="mise"
ASSUME_YES="${ASSUME_YES:-0}"
UPGRADE="${UPGRADE:-0}"
INTERACTIVE=0
CPU_VENDOR=""
ISA_LEVEL=""
SELECTED_OPTIONAL=()

log() { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[0;33mwarning:\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[0;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}

ok() { printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
miss() { printf '  \033[0;33m○\033[0m %s\n' "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

confirm() {
  local prompt="$1" default="${2:-y}" ans hint
  if [ "$INTERACTIVE" != 1 ]; then
    [ "$default" = y ]
    return
  fi
  if [ "$default" = n ]; then hint='[y/N]'; else hint='[Y/n]'; fi
  printf '\033[0;36m??\033[0m %s %s ' "$prompt" "$hint"
  read -r ans </dev/tty || ans=""
  ans="${ans:-$default}"
  case "$ans" in
    y | Y | yes | YES | Yes) return 0 ;;
    *) return 1 ;;
  esac
}

run_step() {
  local label="$1"
  shift
  local rc=0
  set +e
  ( set -e; "$@" )
  rc=$?
  set -e
  if [ "$rc" -ne 0 ]; then
    warn "step failed: $label (continuing)"
  fi
  return 0
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
      DISTRO_FAMILY=macos
      PKG=brew
      ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        WSL=1
      fi
      [ -r /etc/os-release ] || die "untested platform: unidentified Linux"
      . /etc/os-release
      local id="${ID:-}" id_like="${ID_LIKE:-}"
      case "$id" in
        ubuntu | debian | linuxmint | pop)
          OS="$id"
          DISTRO_FAMILY=debian
          PKG=apt
          UBUNTU_VERSION="${VERSION_ID:-}"
          UBUNTU_CODENAME="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
          ;;
        arch | cachyos | endeavouros | manjaro)
          OS="$id"
          DISTRO_FAMILY=arch
          PKG=pacman
          ;;
        ol | rhel | centos | rocky | almalinux | fedora | oracle)
          OS="$id"
          DISTRO_FAMILY=rhel
          PKG=dnf
          have dnf || PKG=yum
          ;;
        nixos)
          OS=nixos
          DISTRO_FAMILY=nixos
          PKG=nix
          ;;
        *)
          case " $id_like " in
            *debian*) OS="$id"; DISTRO_FAMILY=debian; PKG=apt; UBUNTU_CODENAME="${VERSION_CODENAME:-}" ;;
            *arch*) OS="$id"; DISTRO_FAMILY=arch; PKG=pacman ;;
            *rhel* | *fedora*) OS="$id"; DISTRO_FAMILY=rhel; PKG=dnf; have dnf || PKG=yum ;;
            *nixos*) OS=nixos; DISTRO_FAMILY=nixos; PKG=nix ;;
            *) die "untested platform: $id" ;;
          esac
          ;;
      esac
      detect_cpu
      ;;
    *) die "untested platform: $kernel" ;;
  esac
  if [ "$WSL" -eq 1 ]; then
    log "platform: $OS $ARCH (wsl2), pkg=$PKG"
  else
    log "platform: $OS $ARCH, pkg=$PKG"
  fi
}

detect_cpu() {
  CPU_VENDOR="$(awk -F': ' '/^vendor_id/{print $2; exit}' /proc/cpuinfo 2>/dev/null)"
  local model
  model="$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null)"
  if [ "$ARCH" = x86_64 ]; then
    ISA_LEVEL="$(detect_isa_level)"
    log "cpu: ${model:-unknown} (${CPU_VENDOR:-unknown}), supports x86-64-${ISA_LEVEL}"
  else
    log "cpu: ${model:-unknown} (${CPU_VENDOR:-unknown}), $ARCH"
  fi
}

detect_isa_level() {
  local ld help level=v1
  for ld in /lib64/ld-linux-x86-64.so.2 /lib/ld-linux-x86-64.so.2; do
    [ -x "$ld" ] || continue
    help="$("$ld" --help 2>/dev/null)" || continue
    printf '%s\n' "$help" | grep -q 'x86-64-v2 (supported' && level=v2
    printf '%s\n' "$help" | grep -q 'x86-64-v3 (supported' && level=v3
    printf '%s\n' "$help" | grep -q 'x86-64-v4 (supported' && level=v4
    printf '%s' "$level"
    return 0
  done
  local flags
  flags=" $(awk -F': ' '/^flags/{print $2; exit}' /proc/cpuinfo 2>/dev/null) "
  case "$flags" in *' avx512f '*) level=v4 ;; *' avx2 '*) level=v3 ;; *' sse4_2 '*) level=v2 ;; esac
  printf '%s' "$level"
}

choose_shell() {
  if [ -n "${SHELL_CHOICE:-}" ]; then
    case "$SHELL_CHOICE" in zsh | fish) return 0 ;; *) die "invalid SHELL_CHOICE: $SHELL_CHOICE" ;; esac
  fi
  if [ "$INTERACTIVE" != 1 ]; then
    SHELL_CHOICE=zsh
    log "shell: $SHELL_CHOICE (default, non-interactive)"
    return 0
  fi
  local answer
  printf '\nshell to configure [zsh/fish] (default zsh): '
  read -r answer </dev/tty || answer=""
  answer="${answer:-zsh}"
  case "$answer" in
    zsh | fish) SHELL_CHOICE="$answer" ;;
    *) die "invalid shell: $answer" ;;
  esac
  log "shell: $SHELL_CHOICE"
}

apt_install() { sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"; }
dnf_install() { sudo "$PKG" install -y "$@"; }
pac_install() { sudo pacman -S --needed --noconfirm "$@"; }

nix_install() {
  local pkg
  for pkg in "$@"; do
    if nix profile list 2>/dev/null | grep -qiE "(^|[#. ])${pkg}(\$| )"; then
      continue
    fi
    nix profile install "nixpkgs#${pkg}" 2>/dev/null \
      || nix-env -iA "nixpkgs.${pkg}" 2>/dev/null \
      || warn "nix: could not install $pkg (add it to configuration.nix instead)"
  done
}

aur_install() {
  local pkg="$1" tmp
  if pacman -Qi "$pkg" >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "$AUR_HELPER" ] && have "$AUR_HELPER"; then
    "$AUR_HELPER" -S --needed --noconfirm "$pkg"
    return 0
  fi
  log "installing $pkg from aur (makepkg)..."
  tmp="$(mktemp -d)"
  git clone -q "https://aur.archlinux.org/$pkg.git" "$tmp"
  (cd "$tmp" && makepkg -si --noconfirm)
  rm -rf "$tmp"
}

setup_cachyos_repos() {
  if [ "$ARCH" != x86_64 ]; then
    info "cachyos optimized repos are x86_64-only, skipping on $ARCH"
    return 0
  fi
  log "this CPU supports x86-64-${ISA_LEVEL}; cachyos will pick its matching optimized repo"
  if grep -qE '^\[cachyos' /etc/pacman.conf 2>/dev/null; then
    ok "cachyos optimized repos already configured"
  else
    confirm "set up CachyOS optimized (x86-64-${ISA_LEVEL}) repositories?" || {
      info "skipped cachyos repo setup"
      return 0
    }
    log "setting up cachyos optimized repositories..."
    pac_install gawk curl tar
    local tmp
    tmp="$(mktemp -d)"
    if curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz -o "$tmp/cachyos-repo.tar.xz"; then
      tar xf "$tmp/cachyos-repo.tar.xz" -C "$tmp"
      (cd "$tmp/cachyos-repo" && sudo ./cachyos-repo.sh --install) \
        || warn "cachyos-repo.sh failed; continuing with stock arch repos"
      sudo pacman -Syu --noconfirm || true
    else
      warn "could not download cachyos-repo.tar.xz; continuing with stock arch repos"
    fi
    rm -rf "$tmp"
  fi
  setup_native_makepkg
}

setup_native_makepkg() {
  [ "$ARCH" = x86_64 ] || return 0
  local conf=/etc/makepkg.conf
  [ -f "$conf" ] || return 0
  local need_march=1 need_ccache=1 need_makeflags=1
  grep -q '^CFLAGS=.*-march=native' "$conf" 2>/dev/null && need_march=0
  grep -qE '^BUILDENV=.*[^!]ccache' "$conf" 2>/dev/null && need_ccache=0
  grep -qE '^MAKEFLAGS=.*-j' "$conf" 2>/dev/null && need_makeflags=0
  if [ "$need_march" = 0 ] && [ "$need_ccache" = 0 ] && [ "$need_makeflags" = 0 ]; then
    ok "makepkg already tuned (-march=native, ccache, parallel make)"
    return 0
  fi
  confirm "tune /etc/makepkg.conf (-march=native + ccache + parallel make) for faster CPU-optimized builds?" || {
    info "skipped makepkg tuning"
    return 0
  }
  log "tuning makepkg.conf..."
  sudo cp -n "$conf" "$conf.dotfiles.bak" 2>/dev/null || true
  if [ "$need_march" = 1 ]; then
    if grep -qE '^CFLAGS=.*-march=' "$conf"; then
      sudo sed -i -E 's/-march=[a-z0-9-]+/-march=native/g; s/-mtune=[a-z0-9-]+/-mtune=native/g' "$conf"
    else
      {
        echo ''
        echo 'CFLAGS="-march=native -mtune=native -O2 -pipe -fno-plt"'
        echo 'CXXFLAGS="$CFLAGS"'
      } | sudo tee -a "$conf" >/dev/null
    fi
    grep -q 'target-cpu=native' "$conf" 2>/dev/null \
      || echo 'RUSTFLAGS="-C target-cpu=native"' | sudo tee -a "$conf" >/dev/null
  fi
  if [ "$need_ccache" = 1 ]; then
    pac_install ccache
    if grep -qE '^BUILDENV=' "$conf"; then
      sudo sed -i -E 's/!ccache/ccache/' "$conf"
      grep -qE '^BUILDENV=.*ccache' "$conf" \
        || sudo sed -i -E 's/^BUILDENV=\((.*)\)/BUILDENV=(\1 ccache)/' "$conf"
    else
      echo 'BUILDENV=(!distcc color ccache check !sign)' | sudo tee -a "$conf" >/dev/null
    fi
  fi
  if [ "$need_makeflags" = 1 ]; then
    if grep -qE '^#?MAKEFLAGS=' "$conf"; then
      sudo sed -i -E 's/^#?MAKEFLAGS=.*/MAKEFLAGS="-j$(nproc)"/' "$conf"
    else
      echo 'MAKEFLAGS="-j$(nproc)"' | sudo tee -a "$conf" >/dev/null
    fi
  fi
  ok "makepkg tuned: -march=native, ccache, parallel make"
}

setup_paru() {
  if have paru; then
    AUR_HELPER=paru
    return 0
  fi
  if pacman -Si paru >/dev/null 2>&1; then
    pac_install paru && AUR_HELPER=paru && return 0
  fi
  log "bootstrapping paru from aur..."
  pac_install base-devel git
  local tmp
  tmp="$(mktemp -d)"
  git clone -q https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
  (cd "$tmp/paru-bin" && makepkg -si --noconfirm) || warn "paru bootstrap failed; AUR installs will use makepkg"
  rm -rf "$tmp"
  have paru && AUR_HELPER=paru
}

install_homebrew() {
  if ! have brew; then
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

install_mise_linux() {
  if ! have mise && [ ! -x "$HOME/.local/bin/mise" ]; then
    log "installing mise..."
    curl -fsSL https://mise.run | sh
  fi
  if [ -x "$HOME/.local/bin/mise" ]; then
    MISE_BIN="$HOME/.local/bin/mise"
  else
    MISE_BIN="$(command -v mise)"
  fi
  [ "$UPGRADE" = 1 ] && "$MISE_BIN" self-update -y >/dev/null 2>&1 || true
}

install_base_debian() {
  log "updating apt..."
  sudo apt-get update
  log "installing base packages..."
  apt_install \
    build-essential clang clang-format clang-tools lld llvm gdb cmake pkg-config \
    git curl wget ca-certificates gnupg unzip zip tree software-properties-common \
    locales fontconfig fonts-jetbrains-mono \
    autoconf automake libtool m4 libssl-dev libncurses-dev libreadline-dev \
    libyaml-dev zlib1g-dev libffi-dev
  if ! apt-cache policy git 2>/dev/null | grep -q git-core; then
    sudo add-apt-repository -y ppa:git-core/ppa && sudo apt-get update && apt_install git || \
      warn "git-core ppa unavailable, using distro git"
  fi
  sudo locale-gen en_US.UTF-8
  install_nerd_font_manual
}

install_base_arch() {
  log "updating pacman..."
  sudo pacman -Syu --noconfirm
  log "installing base packages..."
  pac_install \
    base-devel clang llvm lld gcc gdb cmake pkgconf \
    git curl wget unzip zip tree \
    openssl ncurses readline libyaml zlib libffi \
    fontconfig ttf-jetbrains-mono ttf-jetbrains-mono-nerd
  if ! grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen; then
    sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    sudo locale-gen
  fi
}

install_base_rhel() {
  log "enabling repos and installing base packages..."
  sudo "$PKG" install -y dnf-plugins-core || true
  sudo "$PKG" install -y epel-release 2>/dev/null || true
  sudo "$PKG" config-manager --set-enabled ol9_codeready_builder 2>/dev/null || \
    sudo "$PKG" config-manager --set-enabled crb 2>/dev/null || \
    sudo "$PKG" config-manager --set-enabled powertools 2>/dev/null || true
  sudo "$PKG" groupinstall -y "Development Tools" 2>/dev/null || sudo "$PKG" group install -y "Development Tools" || true
  dnf_install \
    clang llvm lld gdb cmake pkgconf-pkg-config \
    git curl wget ca-certificates gnupg2 unzip zip tree \
    openssl-devel ncurses-devel readline-devel libyaml-devel zlib-devel libffi-devel \
    fontconfig
  install_nerd_font_manual
}

install_nerd_font_manual() {
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

install_base_nixos() {
  warn "NixOS detected: this performs a best-effort imperative (nix profile) setup."
  info "For system packages and GUI apps prefer configuration.nix / home-manager."
  command -v nix >/dev/null 2>&1 || die "nix command not found"
  nix_install git gcc gnumake binutils pkg-config fontconfig nerd-fonts.jetbrains-mono
}

install_shell_pkg() {
  case "$DISTRO_FAMILY" in
    debian)
      if [ "$SHELL_CHOICE" = fish ]; then
        log "installing fish..."
        sudo add-apt-repository -y ppa:fish-shell/release-4 || warn "fish ppa unavailable, using distro fish"
        sudo apt-get update
        apt_install fish
      else
        log "installing zsh..."
        apt_install zsh
      fi
      ;;
    arch)
      pac_install "$SHELL_CHOICE"
      ;;
    rhel)
      dnf_install "$SHELL_CHOICE"
      ;;
    nixos)
      nix_install "$SHELL_CHOICE"
      ;;
  esac
}


prog_brave() {
  have brave-browser || have brave || {
    log "installing brave browser..."
    case "$DISTRO_FAMILY" in
      debian)
        sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
          https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=$( [ "$ARCH" = arm64 ] && echo arm64 || echo amd64 )] https://brave-browser-apt-release.s3.brave.com/ stable main" \
          | sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
        sudo apt-get update
        apt_install brave-browser
        ;;
      arch)
        if pacman -Si brave-bin >/dev/null 2>&1; then pac_install brave-bin; else aur_install brave-bin; fi
        ;;
      rhel)
        sudo "$PKG" config-manager --add-repo https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo 2>/dev/null || \
          sudo "$PKG" config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
        dnf_install brave-browser
        ;;
    esac
  }
}

prog_ghostty() {
  have ghostty && return 0
  log "installing ghostty..."
  case "$DISTRO_FAMILY" in
    debian)
      if apt-cache show ghostty >/dev/null 2>&1; then
        apt_install ghostty
      elif sudo add-apt-repository -y ppa:mkasberg/ghostty-ubuntu 2>/dev/null; then
        sudo apt-get update && apt_install ghostty
      else
        local deb_arch url tmp
        [ "$ARCH" = arm64 ] && deb_arch=arm64 || deb_arch=amd64
        url="$(curl -fsSL https://api.github.com/repos/mkasberg/ghostty-ubuntu/releases/latest \
          | grep -o "https://[^\"]*_${deb_arch}_${UBUNTU_CODENAME:-$UBUNTU_VERSION}\.deb" | head -n1)"
        if [ -n "$url" ]; then
          tmp="$(mktemp -d)"; curl -fsSL "$url" -o "$tmp/ghostty.deb"; apt_install "$tmp/ghostty.deb"; rm -rf "$tmp"
        else
          warn "no ghostty build for ${UBUNTU_CODENAME:-$UBUNTU_VERSION} $deb_arch, skipping"
        fi
      fi
      ;;
    arch) pac_install ghostty ;;
    rhel) warn "ghostty has no official rhel build (needs zig); skipping" ;;
  esac
}

prog_neovim_deps() {
  log "ensuring neovim plugin dependencies (compiler, git, rg, fd)..."
  return 0
}

prog_rv() {
  if { have rv || [ -x "$HOME/.local/bin/rv" ]; } && [ "$UPGRADE" != 1 ]; then return 0; fi
  log "installing/updating rv (ruby version manager)..."
  curl -LsSf https://rv.dev/install | sh || warn "rv install failed"
}

prog_vscode() {
  have code && { install_vscode_extensions; return 0; }
  log "installing vscode..."
  case "$DISTRO_FAMILY" in
    debian)
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/microsoft.gpg
      echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
        | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
      sudo apt-get update
      apt_install code
      ;;
    arch)
      if pacman -Si visual-studio-code-bin >/dev/null 2>&1; then pac_install visual-studio-code-bin; else aur_install visual-studio-code-bin; fi
      ;;
    rhel)
      sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
      echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" \
        | sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
      dnf_install code
      ;;
  esac
  install_vscode_extensions
}

prog_jetbrains_toolbox() {
  [ -x "$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox" ] && [ "$UPGRADE" != 1 ] && return 0
  log "installing/updating jetbrains toolbox..."
  if [ "$DISTRO_FAMILY" = arch ]; then
    aur_install jetbrains-toolbox
    return 0
  fi
  local url tmp
  url="$(curl -fsSL 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' \
    | grep -o 'https://[^"]*jetbrains-toolbox-[^"]*\.tar\.gz' | head -n1)"
  [ -n "$url" ] || { warn "could not resolve jetbrains toolbox url"; return 0; }
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/tbx.tar.gz"
  tar xzf "$tmp/tbx.tar.gz" -C "$tmp"
  mkdir -p "$HOME/.local/bin"
  install "$tmp"/jetbrains-toolbox-*/jetbrains-toolbox "$HOME/.local/bin/jetbrains-toolbox"
  rm -rf "$tmp"
  info "run 'jetbrains-toolbox' once to finish setup"
}

prog_ngrok() {
  have ngrok && return 0
  log "installing ngrok..."
  case "$DISTRO_FAMILY" in
    debian)
      curl -fsSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo gpg --dearmor -o /usr/share/keyrings/ngrok.gpg
      echo "deb [signed-by=/usr/share/keyrings/ngrok.gpg] https://ngrok-agent.s3.amazonaws.com bookworm main" \
        | sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null
      sudo apt-get update
      apt_install ngrok
      ;;
    arch) aur_install ngrok ;;
    rhel)
      echo -e "[ngrok]\nname=ngrok\nbaseurl=https://ngrok-agent.s3.amazonaws.com/rpm\nenabled=1\ngpgcheck=0" \
        | sudo tee /etc/yum.repos.d/ngrok.repo >/dev/null
      dnf_install ngrok
      ;;
  esac
}

prog_postgres() {
  have psql && return 0
  log "installing postgresql..."
  case "$DISTRO_FAMILY" in
    debian)
      apt_install postgresql-common
      sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y || true
      sudo apt-get update
      apt_install postgresql
      ;;
    arch)
      pac_install postgresql
      init_postgres_arch
      ;;
    rhel)
      dnf_install postgresql postgresql-server
      sudo postgresql-setup --initdb 2>/dev/null || true
      sudo systemctl enable --now postgresql 2>/dev/null || warn "start postgresql manually"
      ;;
  esac
}

init_postgres_arch() {
  if sudo test ! -f /var/lib/postgres/data/PG_VERSION; then
    log "initializing postgresql cluster..."
    sudo -u postgres initdb --locale=en_US.UTF-8 -D /var/lib/postgres/data
  fi
  if have systemctl && pidof systemd >/dev/null 2>&1; then
    sudo systemctl enable --now postgresql
  else
    warn "systemd not running, start postgresql manually"
  fi
}

prog_awscli() {
  if have aws && [ "$UPGRADE" != 1 ]; then return 0; fi
  if [ "$DISTRO_FAMILY" = arch ] && pacman -Si aws-cli >/dev/null 2>&1; then
    pac_install aws-cli
    return 0
  fi
  log "installing/updating awscli..."
  local tmp uarch
  [ "$ARCH" = arm64 ] && uarch=aarch64 || uarch=x86_64
  tmp="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${uarch}.zip" -o "$tmp/awscliv2.zip"
  unzip -q "$tmp/awscliv2.zip" -d "$tmp"
  sudo "$tmp/aws/install" --update
  rm -rf "$tmp"
}

prog_ollama() {
  if have ollama && [ "$UPGRADE" != 1 ]; then return 0; fi
  log "installing/updating ollama..."
  if [ "$DISTRO_FAMILY" = arch ]; then
    pac_install ollama
    have systemctl && pidof systemd >/dev/null 2>&1 && sudo systemctl enable --now ollama || true
  else
    curl -fsSL https://ollama.com/install.sh | sh
  fi
}

prog_rubyfmt() {
  if have rubyfmt && [ "$UPGRADE" != 1 ]; then return 0; fi
  if [ "$DISTRO_FAMILY" = arch ]; then
    aur_install rubyfmt && return 0
  fi
  log "installing/updating rubyfmt..."
  local tag uarch tmp
  [ "$ARCH" = arm64 ] && uarch=aarch64 || uarch=x86_64
  tag="$(curl -fsSL https://api.github.com/repos/fables-tales/rubyfmt/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"
  [ -n "$tag" ] || { warn "could not resolve rubyfmt release"; return 0; }
  tmp="$(mktemp -d)"
  if curl -fsSL "https://github.com/fables-tales/rubyfmt/releases/download/${tag}/rubyfmt-${tag}-Linux-${uarch}.tar.gz" -o "$tmp/rubyfmt.tar.gz"; then
    tar xzf "$tmp/rubyfmt.tar.gz" -C "$tmp"
    sudo install "$tmp"/rubyfmt-main "/usr/local/bin/rubyfmt" 2>/dev/null \
      || sudo install "$(find "$tmp" -name 'rubyfmt*' -type f | head -n1)" /usr/local/bin/rubyfmt
  else
    warn "rubyfmt prebuilt binary not found for $uarch"
  fi
  rm -rf "$tmp"
}

prog_swi_prolog() {
  have swipl && return 0
  log "installing swi-prolog..."
  case "$DISTRO_FAMILY" in
    debian)
      sudo apt-add-repository -y ppa:swi-prolog/stable 2>/dev/null || true
      sudo apt-get update
      apt_install swi-prolog
      ;;
    arch) pac_install swi-prolog ;;
    rhel)
      if have flatpak; then
        flatpak install -y flathub org.swi_prolog.swipl || warn "swi-prolog flatpak failed"
      else
        warn "swi-prolog has no dnf package; install flatpak then 'flatpak install flathub org.swi_prolog.swipl'"
      fi
      ;;
  esac
}

prog_latex() {
  have latexmk && return 0
  log "installing full latex (texlive)..."
  case "$DISTRO_FAMILY" in
    debian)
      apt_install texlive texlive-latex-extra texlive-fonts-extra texlive-bibtex-extra \
        texlive-science texlive-xetex texlive-luatex latexmk biber chktex
      ;;
    arch)
      pac_install texlive-meta biber
      ;;
    rhel)
      dnf_install texlive-scheme-full latexmk biber 2>/dev/null || \
        dnf_install texlive texlive-latex texlive-collection-latexextra latexmk biber
      ;;
    nixos)
      nix_install texliveFull
      ;;
  esac
}

prog_google_drive() {
  warn "google drive has no official linux desktop client."
  case "$DISTRO_FAMILY" in
    arch) info "alternatives: 'paru -S google-drive-ocamlfuse' or rclone (mise/pacman)" ;;
    *) info "alternatives: rclone (https://rclone.org) with a gdrive remote, or use the web client" ;;
  esac
}

prog_intel_undervolt() {
  if [ "$CPU_VENDOR" != GenuineIntel ]; then
    info "non-Intel CPU ($CPU_VENDOR), skipping intel-undervolt"
    return 0
  fi
  if [ "$DISTRO_FAMILY" = nixos ]; then
    warn "on NixOS, manage intel-undervolt declaratively in configuration.nix:"
    info 'services.undervolt = { enable = true; package = pkgs.intel-undervolt; };'
    info "then set power limits via its config; skipping imperative setup."
    return 0
  fi
  install_intel_undervolt_pkg
  have intel-undervolt || { warn "intel-undervolt unavailable, skipping config"; return 0; }
  configure_intel_undervolt
}

install_intel_undervolt_pkg() {
  have intel-undervolt && { ok "intel-undervolt already installed"; return 0; }
  log "installing intel-undervolt..."
  case "$DISTRO_FAMILY" in
    arch)
      if pacman -Si intel-undervolt >/dev/null 2>&1; then pac_install intel-undervolt
      else aur_install intel-undervolt; fi
      ;;
    debian)
      if apt-cache show intel-undervolt >/dev/null 2>&1; then apt_install intel-undervolt
      else build_intel_undervolt_from_source; fi
      ;;
    rhel)
      dnf_install intel-undervolt 2>/dev/null || build_intel_undervolt_from_source
      ;;
  esac
}

build_intel_undervolt_from_source() {
  log "building intel-undervolt from source (kitsunyan/intel-undervolt)..."
  case "$DISTRO_FAMILY" in
    debian) apt_install build-essential pkg-config ;;
    rhel) dnf_install gcc make pkgconf-pkg-config ;;
  esac
  local tmp
  tmp="$(mktemp -d)"
  git clone -q https://github.com/kitsunyan/intel-undervolt "$tmp/iuv"
  (cd "$tmp/iuv" && make && sudo make install)
  rm -rf "$tmp"
}

configure_intel_undervolt() {
  local conf=/etc/intel-undervolt.conf
  [ -f "$conf" ] || { warn "$conf missing after install, skipping config"; return 0; }
  sudo cp -n "$conf" "$conf.dotfiles.bak" 2>/dev/null || true

  if grep -qE '^[[:space:]]*power[[:space:]]+package[[:space:]]+30/8[[:space:]]+22/10' "$conf"; then
    ok "power package limit already 30/8 22/10"
  else
    log "setting 'power package 30/8 22/10'..."
    sudo sed -i -E '/^[[:space:]]*power[[:space:]]+package[[:space:]]+/d' "$conf"
    echo 'power package 30/8 22/10' | sudo tee -a "$conf" >/dev/null
  fi

  sudo sed -i -E 's/^([[:space:]]*)daemon[[:space:]]+undervolt:once/\1# daemon undervolt:once/' "$conf"
  sudo sed -i -E 's/^([[:space:]]*)daemon[[:space:]]+tjoffset/\1# daemon tjoffset/' "$conf"
  if grep -qE '^[[:space:]]*#[[:space:]]*daemon[[:space:]]+power\b' "$conf"; then
    sudo sed -i -E 's/^([[:space:]]*)#[[:space:]]*daemon[[:space:]]+power\b/\1daemon power/' "$conf"
  elif ! grep -qE '^[[:space:]]*daemon[[:space:]]+power\b' "$conf"; then
    echo 'daemon power' | sudo tee -a "$conf" >/dev/null
  fi

  sudo intel-undervolt apply || warn "intel-undervolt apply failed"
  if have systemctl && pidof systemd >/dev/null 2>&1; then
    sudo systemctl enable --now intel-undervolt || warn "could not enable intel-undervolt.service"
  else
    info "systemd not active; run 'sudo systemctl enable --now intel-undervolt' later"
  fi
}


CORE_KEYS=(brave ghostty neovim_deps rv)

optional_menu_entries() {
  cat <<'EOF'
vscode|Visual Studio Code + extensions|on
latex|Full LaTeX (TeX Live) + latexmk/biber/chktex|on
syswatch|syswatch system monitor (top replacement)|on
awscli|AWS CLI v2|on
postgres|PostgreSQL server|off
ollama|Ollama (local LLMs)|off
rubyfmt|rubyfmt (Ruby formatter)|off
swi_prolog|SWI-Prolog|off
ngrok|ngrok tunneling|off
jetbrains_toolbox|JetBrains Toolbox|off
google_drive|Google Drive (alternatives info)|off
EOF
  if [ "$CPU_VENDOR" = GenuineIntel ]; then
    echo 'intel_undervolt|intel-undervolt + power limits 30/8 22/10|on'
  fi
}

comp_label() {
  case "$1" in
    git) echo "git (latest)" ;;
    brave) echo "Brave Browser" ;;
    ghostty) echo "Ghostty terminal" ;;
    neovim_deps) echo "Neovim build dependencies" ;;
    rv) echo "rv (Ruby version manager)" ;;
    *)
      local k l
      while IFS='|' read -r k l _; do
        [ "$k" = "$1" ] && { echo "$l"; return 0; }
      done < <(optional_menu_entries)
      echo "$1"
      ;;
  esac
}

_ver() {
  local c="$1"
  shift
  have "$c" || return 1
  "$c" "$@" 2>/dev/null | head -n1
}

comp_status() {
  case "$1" in
    git) _ver git --version ;;
    brave) _ver brave-browser --version || _ver brave --version ;;
    ghostty) _ver ghostty --version ;;
    neovim_deps) { have gcc || have cc || have clang; } && echo "toolchain present" ;;
    rv) _ver rv --version || { [ -x "$HOME/.local/bin/rv" ] && "$HOME/.local/bin/rv" --version 2>/dev/null | head -n1; } ;;
    vscode) _ver code --version ;;
    latex) _ver latexmk --version || _ver tex --version ;;
    syswatch) have syswatch && echo installed ;;
    awscli) _ver aws --version ;;
    postgres) _ver psql --version ;;
    ollama) _ver ollama --version ;;
    rubyfmt) have rubyfmt && { rubyfmt --version 2>/dev/null | head -n1 || echo installed; } ;;
    swi_prolog) _ver swipl --version ;;
    ngrok) _ver ngrok --version ;;
    jetbrains_toolbox) { [ -x "$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox" ] || have jetbrains-toolbox; } && echo installed ;;
    intel_undervolt) have intel-undervolt && echo installed ;;
    google_drive) return 1 ;;
    *) return 1 ;;
  esac
}

comp_install() {
  case "$1" in
    brave) prog_brave ;;
    ghostty) prog_ghostty ;;
    neovim_deps) prog_neovim_deps ;;
    rv) prog_rv ;;
    vscode) prog_vscode ;;
    latex) prog_latex ;;
    syswatch) install_syswatch ;;
    awscli) prog_awscli ;;
    postgres) prog_postgres ;;
    ollama) prog_ollama ;;
    rubyfmt) prog_rubyfmt ;;
    swi_prolog) prog_swi_prolog ;;
    ngrok) prog_ngrok ;;
    jetbrains_toolbox) prog_jetbrains_toolbox ;;
    google_drive) prog_google_drive ;;
    intel_undervolt) prog_intel_undervolt ;;
  esac
}

gated_install() {
  local key="$1" label ver
  label="$(comp_label "$key")"
  if ver="$(comp_status "$key" 2>/dev/null)" && [ -n "$ver" ]; then
    ok "$label — already installed ($ver)"
    if [ "$UPGRADE" = 1 ] && [ "$key" != google_drive ]; then
      confirm "re-run installer to upgrade $label?" n && run_step "$label" comp_install "$key"
    fi
    return 0
  fi
  if confirm "Proceed installing $label?"; then
    run_step "$label" comp_install "$key"
  else
    info "skipped $label"
  fi
}

print_status() {
  log "current status on $OS $ARCH (x86-64-${ISA_LEVEL:-n/a}):"
  local key ver
  printf '  core programs:\n'
  if ver="$(comp_status git 2>/dev/null)" && [ -n "$ver" ]; then
    ok "git (latest) — $ver"
  else
    miss "git (latest) — not installed"
  fi
  for key in "${CORE_KEYS[@]}"; do
    if ver="$(comp_status "$key" 2>/dev/null)" && [ -n "$ver" ]; then
      ok "$(comp_label "$key") — $ver"
    else
      miss "$(comp_label "$key") — not installed"
    fi
  done
  printf '  cli tools (via mise):\n'
  local tool
  for tool in mise bat fd fzf rg eza delta zoxide nvim shellcheck uv yq jq just tre mdt spf dust duf procs sd hyperfine sccache; do
    if have "$tool"; then ok "$tool"; else miss "$tool — will be installed by mise"; fi
  done
  printf '  optional programs:\n'
  local k l
  while IFS='|' read -r k l _; do
    if ver="$(comp_status "$k" 2>/dev/null)" && [ -n "$ver" ]; then
      ok "$l — $ver"
    else
      miss "$l — not installed"
    fi
  done < <(optional_menu_entries)
}

select_optional() {
  local -a keys descs states inst
  local key desc def
  while IFS='|' read -r key desc def; do
    [ -n "$key" ] || continue
    keys+=("$key"); descs+=("$desc")
    [ "$def" = on ] && states+=("on") || states+=("off")
    if comp_status "$key" >/dev/null 2>&1; then inst+=("yes"); else inst+=("no"); fi
  done < <(optional_menu_entries)

  if [ "$INTERACTIVE" != 1 ]; then
    local i
    for i in "${!keys[@]}"; do
      [ "${states[$i]}" = on ] && SELECTED_OPTIONAL+=("${keys[$i]}")
    done
    return 0
  fi

  while true; do
    printf '\nOptional programs ([x]=will attempt, (installed)=already present):\n'
    local i
    for i in "${!keys[@]}"; do
      local tag=''
      [ "${inst[$i]}" = yes ] && tag=' \033[0;32m(installed)\033[0m'
      printf '  %2d) [%s] %b%b\n' "$((i + 1))" \
        "$([ "${states[$i]}" = on ] && echo x || echo ' ')" "${descs[$i]}" "$tag"
    done
    printf '\nToggle by number (e.g. "1 3 5"), "a" all, "n" none, ENTER to accept: '
    local input
    read -r input </dev/tty || input=""
    case "$input" in
      "") break ;;
      a | A) for i in "${!states[@]}"; do states[$i]=on; done ;;
      n | N) for i in "${!states[@]}"; do states[$i]=off; done ;;
      *)
        local tok
        for tok in $input; do
          if [[ "$tok" =~ ^[0-9]+$ ]] && [ "$tok" -ge 1 ] && [ "$tok" -le "${#keys[@]}" ]; then
            local idx=$((tok - 1))
            [ "${states[$idx]}" = on ] && states[$idx]=off || states[$idx]=on
          fi
        done
        ;;
    esac
  done

  local i
  for i in "${!keys[@]}"; do
    [ "${states[$i]}" = on ] && SELECTED_OPTIONAL+=("${keys[$i]}")
  done
}

install_selected_optional() {
  local key
  for key in "${SELECTED_OPTIONAL[@]}"; do
    gated_install "$key"
  done
}

install_syswatch() {
  have syswatch && return 0
  log "installing syswatch..."
  if [ "$DISTRO_FAMILY" = arch ]; then
    aur_install syswatch && return 0
  fi
  if [ -n "${MISE_BIN:-}" ]; then
    "$MISE_BIN" use -g "github:matthart1983/syswatch" 2>/dev/null && return 0
  fi
  warn "syswatch could not be installed automatically"
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
  rm -f "$HOME/.config/mise/conf.d/cargo.toml"
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
  [ "$UPGRADE" = 1 ] && { log "upgrading mise tools..."; MISE_YES=1 "$MISE_BIN" upgrade 2>/dev/null || true; }
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
  if ! have code; then
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
  [ -n "$shell_path" ] || { warn "$SHELL_CHOICE not found on PATH, skipping default-shell change"; return 0; }
  if [ "$OS" = nixos ]; then
    current="$(current_login_shell)"
    [ "$current" = "$shell_path" ] && { log "default shell already $shell_path"; return 0; }
    warn "on NixOS set your login shell declaratively, e.g.:"
    info "users.users.$USER.shell = pkgs.$SHELL_CHOICE;"
    return 0
  fi
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
    if ! confirm "set $SHELL_CHOICE ($shell_path) as your default login shell?"; then
      info "skipped default-shell change"
      return 0
    fi
    sudo chsh -s "$shell_path" "$USER" || warn "chsh failed, run: sudo chsh -s $shell_path $USER"
  fi
}

install_linux() {
  print_status

  if confirm "Proceed installing base system packages (toolchain, fonts, locale)?"; then
    case "$DISTRO_FAMILY" in
      debian) run_step "base packages" install_base_debian ;;
      arch)
        if [ "$ARCH" = x86_64 ]; then setup_cachyos_repos; fi
        setup_paru
        run_step "base packages" install_base_arch
        ;;
      rhel) run_step "base packages" install_base_rhel ;;
      nixos) run_step "base packages" install_base_nixos ;;
    esac
  else
    info "skipped base system packages"
  fi

  run_step "shell package" install_shell_pkg

  log "core programs:"
  local key
  for key in "${CORE_KEYS[@]}"; do
    gated_install "$key"
  done

  select_optional
  if [ "${#SELECTED_OPTIONAL[@]}" -gt 0 ]; then
    log "optional programs:"
    install_selected_optional
  fi
}

usage() {
  cat <<EOF
Usage: install.sh [--shell zsh|fish] [--yes] [--upgrade] [--status]
  --shell    Pick shell non-interactively (zsh or fish).
  --yes,-y   Accept defaults, no prompts (non-interactive).
  --upgrade  Also re-run installers for already-installed non-repo tools.
  --status   Only print what is installed vs missing, then exit (Linux).
  -h,--help  Show this help.
EOF
}

main() {
  [ "$(id -u)" -ne 0 ] || die "do not run as root"
  local status_only=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --shell) SHELL_CHOICE="${2:-}"; shift 2 ;;
      --shell=*) SHELL_CHOICE="${1#*=}"; shift ;;
      --yes | -y) ASSUME_YES=1; shift ;;
      --upgrade) UPGRADE=1; shift ;;
      --status) status_only=1; shift ;;
      -h | --help) usage; exit 0 ;;
      *) die "unknown argument: $1" ;;
    esac
  done

  if [ -t 0 ] && [ "$ASSUME_YES" != 1 ]; then INTERACTIVE=1; fi

  log "bootstrapping system..."
  detect_platform

  if [ "$status_only" = 1 ]; then
    [ "$OS" = macos ] && die "--status is for Linux; on macOS use 'brew bundle check'"
    print_status
    exit 0
  fi

  choose_shell
  mkdir -p "$HOME/Repos"

  if [ "$OS" = macos ]; then
    install_macos
  else
    install_mise_linux
    install_linux
  fi

  if [ "$SHELL_CHOICE" = zsh ]; then
    install_oh_my_zsh
  fi

  link_dotfiles

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
