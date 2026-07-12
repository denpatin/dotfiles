#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/denpatin/dotfiles"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
PROFILE=""
KIND="${KIND:-}"
WSL_DETECTED=0
ARCH=""
ISA_LEVEL=""
CPU_VENDOR=""
CPU_MODEL=""
IUV_TUNED_MODEL="i7-1370P"
SHELL_CHOICE="${SHELL_CHOICE:-}"
ASSUME_YES="${ASSUME_YES:-0}"
UPGRADE="${UPGRADE:-0}"
INTERACTIVE=0
MISE_BIN="mise"
UBUNTU_CODENAME=""
SELECTED_OPTIONAL=()
RESULT_DONE=()
RESULT_PRESENT=()
RESULT_SKIP=()
RESULT_FAIL=()
LAST_STEP_RC=0
CONFIGS_LINKED=0

log() { printf '\033[0;32m==>\033[0m %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[0;33mwarning:\033[0m %s\n' "$*" >&2; }
ok() { printf '  \033[0;32m✓\033[0m %s\n' "$*"; }
miss() { printf '  \033[0;33m○\033[0m %s\n' "$*"; }
die() {
  printf '\033[0;31merror:\033[0m %s\n' "$*" >&2
  exit 1
}

have() { command -v "$1" >/dev/null 2>&1; }

record_done() { RESULT_DONE+=("$1"); }
record_present() { RESULT_PRESENT+=("$1"); }
record_skip() { RESULT_SKIP+=("$1"); }
record_fail() { RESULT_FAIL+=("$1"$'\t'"${2:-re-run ./install.sh to retry}"); }

join_comma() {
  local out="" item
  for item in "$@"; do
    if [ -z "$out" ]; then out="$item"; else out="$out, $item"; fi
  done
  printf '%s' "$out"
}

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

section_confirm() {
  [ "$PROFILE" = macos ] && return 0
  confirm "$1"
}

run_step() {
  local label="$1"
  shift
  set +e
  (
    set -e
    "$@"
  )
  LAST_STEP_RC=$?
  set -e
  if [ "$LAST_STEP_RC" -ne 0 ]; then
    warn "step failed: $label — continuing (re-run ./install.sh to resume)"
  fi
  return 0
}

tracked_step() {
  local label="$1" hint="$2"
  shift 2
  run_step "$label" "$@"
  if [ "$LAST_STEP_RC" -ne 0 ]; then
    record_fail "$label" "$hint"
  else
    record_done "$label"
  fi
}

detect_platform() {
  local kernel machine id
  kernel="$(uname -s)"
  machine="$(uname -m)"
  case "$machine" in
    arm64 | aarch64) ARCH=arm64 ;;
    x86_64 | amd64) ARCH=x86_64 ;;
    *) die "unsupported architecture: $machine" ;;
  esac

  case "$kernel" in
    Darwin)
      [ "$ARCH" = arm64 ] || die "unsupported platform: macOS on $machine"
      PROFILE=macos
      ;;
    Linux)
      [ -r /etc/os-release ] || die "unsupported platform: unidentified Linux"
      . /etc/os-release
      id="${ID:-}"
      case "$id" in
        cachyos) PROFILE=cachyos ;;
        ubuntu | debian | linuxmint | pop) PROFILE=ubuntu ;;
        arch) PROFILE=cachyos ;;
        *)
          case " ${ID_LIKE:-} " in
            *arch*) PROFILE=cachyos ;;
            *debian*) PROFILE=ubuntu ;;
            *) die "unsupported platform: $id (only macOS, CachyOS and Ubuntu are supported)" ;;
          esac
          ;;
      esac
      UBUNTU_CODENAME="${VERSION_CODENAME:-}"
      if grep -qi microsoft /proc/version 2>/dev/null; then
        WSL_DETECTED=1
      fi
      detect_cpu
      ;;
    *) die "unsupported platform: $kernel" ;;
  esac
  log "distro: $PROFILE ($ARCH)"
}

want_gui() { [ "$KIND" = gui ]; }
want_hw() { [ "$KIND" != wsl ] && [ "$PROFILE" != macos ]; }

choose_kind() {
  if [ "$PROFILE" = macos ]; then
    KIND=gui
    return 0
  fi
  if [ -n "$KIND" ]; then
    case "$KIND" in
      gui | cli | wsl) ;;
      *) die "invalid KIND: $KIND (gui, cli or wsl)" ;;
    esac
  elif [ "$WSL_DETECTED" = 1 ]; then
    KIND=wsl
  elif [ "$INTERACTIVE" != 1 ]; then
    die "non-interactive run needs an explicit --kind gui|cli|wsl"
  else
    local answer
    printf '\nWhat kind of system is this?\n'
    printf '  1) standalone with GUI   — desktop apps, drivers, kernel and power tuning\n'
    printf '  2) standalone, CLI only  — drivers, kernel and power tuning, no desktop apps\n'
    printf '  3) WSL                   — no desktop apps, no kernel or hardware tuning\n'
    while [ -z "$KIND" ]; do
      printf '\nchoice [1/2/3]: '
      read -r answer </dev/tty || answer=""
      case "$answer" in
        1) KIND=gui ;;
        2) KIND=cli ;;
        3) KIND=wsl ;;
        *) warn "pick 1, 2 or 3" ;;
      esac
    done
  fi
  case "$KIND" in
    gui) log "system: standalone with GUI" ;;
    cli) log "system: standalone, CLI only" ;;
    wsl) log "system: WSL (no GUI, no hardware tuning)" ;;
  esac
  if [ "$WSL_DETECTED" = 1 ] && [ "$KIND" != wsl ]; then
    warn "WSL detected but '$KIND' selected — kernel and hardware steps will fail under WSL"
  fi
}

detect_cpu() {
  CPU_VENDOR="$(awk -F': ' '/^vendor_id/{print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
  CPU_MODEL="$(awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo 2>/dev/null || true)"
  if [ "$ARCH" = x86_64 ]; then
    ISA_LEVEL="$(detect_isa_level)"
    log "cpu: ${CPU_MODEL:-unknown} — supports x86-64-${ISA_LEVEL}"
  else
    log "cpu: ${CPU_MODEL:-unknown} ($ARCH)"
  fi
}

detect_isa_level() {
  local ld help level=v1 flags
  for ld in /lib64/ld-linux-x86-64.so.2 /lib/ld-linux-x86-64.so.2; do
    [ -x "$ld" ] || continue
    help="$("$ld" --help 2>/dev/null)" || continue
    printf '%s\n' "$help" | grep -q 'x86-64-v2 (supported' && level=v2
    printf '%s\n' "$help" | grep -q 'x86-64-v3 (supported' && level=v3
    printf '%s\n' "$help" | grep -q 'x86-64-v4 (supported' && level=v4
    printf '%s' "$level"
    return 0
  done
  flags=" $(awk -F': ' '/^flags/{print $2; exit}' /proc/cpuinfo 2>/dev/null || true) "
  case "$flags" in
    *' avx512f '*) level=v4 ;;
    *' avx2 '*) level=v3 ;;
    *' sse4_2 '*) level=v2 ;;
  esac
  printf '%s' "$level"
}

ensure_git() {
  have git && return 0
  log "installing git..."
  case "$PROFILE" in
    macos)
      install_homebrew
      brew install git
      ;;
    cachyos)
      sudo pacman -Sy --needed --noconfirm git
      ;;
    ubuntu)
      sudo apt-get update
      sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git ca-certificates
      ;;
  esac
  have git || die "could not install git"
}

bootstrap_repo() {
  ensure_git
  if [ -d "$DOTFILES_DIR/.git" ]; then
    log "updating existing clone at $DOTFILES_DIR..."
    git -C "$DOTFILES_DIR" pull --ff-only || warn "could not fast-forward $DOTFILES_DIR, using it as-is"
  elif [ -e "$DOTFILES_DIR" ]; then
    die "$DOTFILES_DIR exists but is not a git clone — move it aside and re-run"
  else
    log "cloning $REPO_URL into $DOTFILES_DIR..."
    git clone "$REPO_URL" "$DOTFILES_DIR"
  fi
  chmod +x "$DOTFILES_DIR/install.sh"
  log "handing off to $DOTFILES_DIR/install.sh"
  exec bash "$DOTFILES_DIR/install.sh" "$@"
}

paru_install() {
  paru -S --needed --noconfirm "$@"
}

apt_install() {
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

pkg_install() {
  case "$PROFILE" in
    cachyos) paru_install "$@" ;;
    ubuntu) apt_install "$@" ;;
    macos) brew install "$@" ;;
  esac
}

append_once() {
  local line="$1" file="$2"
  if sudo test -f "$file" && sudo grep -qxF "$line" "$file"; then
    return 0
  fi
  printf '%s\n' "$line" | sudo tee -a "$file" >/dev/null
}

choose_shell() {
  if [ -n "$SHELL_CHOICE" ]; then
    case "$SHELL_CHOICE" in
      zsh | fish) ;;
      *) die "invalid SHELL_CHOICE: $SHELL_CHOICE" ;;
    esac
  elif [ "$INTERACTIVE" != 1 ]; then
    SHELL_CHOICE=fish
  else
    local answer
    printf '\nshell to configure [fish/zsh] (default fish): '
    read -r answer </dev/tty || answer=""
    answer="${answer:-fish}"
    case "$answer" in
      zsh | fish) SHELL_CHOICE="$answer" ;;
      *) die "invalid shell: $answer" ;;
    esac
  fi
  log "shell: $SHELL_CHOICE"
}

install_shell_pkg() {
  if have "$SHELL_CHOICE"; then
    ok "$SHELL_CHOICE already installed ($("$SHELL_CHOICE" --version 2>/dev/null | head -n1))"
    return 0
  fi
  log "installing $SHELL_CHOICE..."
  case "$PROFILE" in
    macos) brew install "$SHELL_CHOICE" ;;
    cachyos) paru_install "$SHELL_CHOICE" ;;
    ubuntu)
      if [ "$SHELL_CHOICE" = fish ]; then
        sudo add-apt-repository -y ppa:fish-shell/release-4 2>/dev/null || warn "fish ppa unavailable, using distro fish"
        sudo apt-get update
      fi
      apt_install "$SHELL_CHOICE"
      ;;
  esac
  have "$SHELL_CHOICE" || die "could not install $SHELL_CHOICE"
}

current_login_shell() {
  if [ "$PROFILE" = macos ]; then
    dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}'
  else
    getent passwd "$USER" | cut -d: -f7
  fi
}

set_default_shell() {
  local shell_path current
  shell_path="$(command -v "$SHELL_CHOICE")"
  [ -n "$shell_path" ] || {
    warn "$SHELL_CHOICE not on PATH, skipping default-shell change"
    return 0
  }
  if ! grep -qxF "$shell_path" /etc/shells 2>/dev/null; then
    log "registering $shell_path in /etc/shells..."
    append_once "$shell_path" /etc/shells
  fi
  current="$(current_login_shell)"
  if [ "$current" = "$shell_path" ]; then
    ok "default shell already $shell_path"
    return 0
  fi
  log "setting default shell to $shell_path..."
  if [ "$PROFILE" = macos ]; then
    chsh -s "$shell_path" || warn "chsh failed, run: chsh -s $shell_path"
  else
    sudo chsh -s "$shell_path" "$USER" || warn "chsh failed, run: sudo chsh -s $shell_path $USER"
  fi
}

install_homebrew() {
  if ! have brew; then
    log "installing homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  [ -x /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
}

install_macos() {
  install_homebrew
  log "running brew bundle..."
  if ! brew bundle --file="$DOTFILES_DIR/Brewfile"; then
    warn "brew bundle finished with errors, rerun 'brew bundle' later"
  fi
}

setup_paru() {
  if have paru; then
    ok "paru already installed"
    return 0
  fi
  log "bootstrapping paru..."
  sudo pacman -Sy --needed --noconfirm base-devel git
  if pacman -Si paru >/dev/null 2>&1; then
    sudo pacman -S --needed --noconfirm paru
  else
    local tmp
    tmp="$(mktemp -d)"
    git clone -q https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
    (cd "$tmp/paru-bin" && makepkg -si --noconfirm)
    rm -rf "$tmp"
  fi
  have paru || die "could not bootstrap paru"
}

setup_cachyos_repos() {
  [ "$ARCH" = x86_64 ] || return 0
  if [ "$ISA_LEVEL" != v3 ] && [ "$ISA_LEVEL" != v4 ]; then
    die "this CPU reports only x86-64-${ISA_LEVEL}; CachyOS optimized repos need v3+"
  fi
  if grep -qE "^\[cachyos.*-v[34]\]" /etc/pacman.conf 2>/dev/null; then
    ok "cachyos x86-64-${ISA_LEVEL} repos already configured"
    return 0
  fi
  log "setting up CachyOS x86-64-${ISA_LEVEL} optimized repositories..."
  sudo pacman -Sy --needed --noconfirm gawk curl tar
  local tmp
  tmp="$(mktemp -d)"
  if curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz -o "$tmp/cachyos-repo.tar.xz"; then
    tar xf "$tmp/cachyos-repo.tar.xz" -C "$tmp"
    (cd "$tmp/cachyos-repo" && sudo ./cachyos-repo.sh --install) \
      || warn "cachyos-repo.sh failed; continuing with stock repos"
    sudo pacman -Syu --noconfirm || true
  else
    warn "could not download cachyos-repo.tar.xz; continuing with stock repos"
  fi
  rm -rf "$tmp"
  grep -qE "^\[cachyos.*-v[34]\]" /etc/pacman.conf 2>/dev/null \
    || warn "optimized repos not present in /etc/pacman.conf — packages will be generic x86-64"
}

setup_native_makepkg() {
  local dropin=/etc/makepkg.conf.d/99-native.conf
  sudo mkdir -p /etc/makepkg.conf.d
  sudo install -m 0644 "$DOTFILES_DIR/linux/makepkg-native.conf" "$dropin"
  ok "makepkg drop-in installed: -march=native -O3, LTO, ccache, RUSTFLAGS, GOAMD64=v3"
}

install_cachyos_kernel() {
  if uname -r | grep -q 'bore'; then
    ok "BORE kernel already running ($(uname -r))"
  fi
  if pacman -Qq linux-cachyos-bore-lto >/dev/null 2>&1; then
    ok "linux-cachyos-bore-lto already installed"
    return 0
  fi
  log "installing linux-cachyos-bore-lto (BORE + Clang ThinLTO, x86-64-${ISA_LEVEL})..."
  paru_install linux-cachyos-bore-lto linux-cachyos-bore-lto-headers
  info "previous kernel is kept as a fallback entry in the bootloader"
  if have limine-update; then
    sudo limine-update || true
  elif [ -d /boot/grub ] && have grub-mkconfig; then
    sudo grub-mkconfig -o /boot/grub/grub.cfg || true
  fi
}

cachyos_pacman_tools() {
  printf '%s\n' \
    bat fd hurl just ripgrep xh yazi zellij zoxide \
    neovim git-delta dust duf fzf grex choose hyperfine jaq jless jujutsu \
    sccache sd tmux typst uv watchexec broot atac tokei \
    ugrep jq ghostty git ccache cmake mold ninja gdb rsync starship
}

install_cachyos_tools() {
  log "installing CPU-optimized (x86-64-${ISA_LEVEL}) tools from CachyOS repos..."
  local pkgs=() p
  while IFS= read -r p; do pkgs+=("$p"); done < <(cachyos_pacman_tools)
  paru_install "${pkgs[@]}" || warn "some optimized packages failed; mise will not cover them"
}

install_base_cachyos() {
  log "installing base toolchain..."
  paru_install \
    base-devel clang llvm lld gcc gcc-fortran gdb pkgconf \
    curl wget unzip zip \
    openssl ncurses readline libyaml zlib libffi \
    fontconfig ttf-jetbrains-mono ttf-jetbrains-mono-nerd \
    shelly
  if ! grep -q '^en_US.UTF-8 UTF-8' /etc/locale.gen; then
    sudo sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
    sudo locale-gen
  fi
}

install_base_ubuntu() {
  log "updating apt..."
  sudo apt-get update
  log "installing base toolchain..."
  apt_install \
    build-essential clang clang-format clang-tools lld llvm gdb cmake pkg-config mold \
    curl wget ca-certificates gnupg unzip zip tree software-properties-common \
    locales fontconfig fonts-jetbrains-mono rsync \
    autoconf automake libtool m4 libssl-dev libncurses-dev libreadline-dev \
    libyaml-dev zlib1g-dev libffi-dev
  if ! apt-cache policy git 2>/dev/null | grep -q git-core; then
    if ! {
      sudo add-apt-repository -y ppa:git-core/ppa && sudo apt-get update && apt_install git
    }; then
      warn "git-core ppa unavailable, using distro git"
    fi
  fi
  sudo locale-gen en_US.UTF-8
  apt_install ugrep jq ccache || warn "some base packages unavailable via apt"
  return 0
}

install_nerd_font() {
  if fc-list 2>/dev/null | grep -q "JetBrainsMono Nerd Font"; then
    ok "JetBrainsMono Nerd Font already installed"
    return 0
  fi
  log "installing JetBrainsMono Nerd Font..."
  local font_dir="$HOME/.local/share/fonts/JetBrainsMonoNerd" tmp
  mkdir -p "$font_dir"
  tmp="$(mktemp -d)"
  if curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -o "$tmp/JetBrainsMono.zip"; then
    unzip -o -q "$tmp/JetBrainsMono.zip" -d "$font_dir"
    fc-cache -f >/dev/null
  else
    warn "could not download JetBrainsMono Nerd Font"
  fi
  rm -rf "$tmp"
}

setup_ram_tmpfs() {
  local line="tmpfs /ram tmpfs rw,nosuid,nodev,size=32G,mode=1777 0 0"
  sudo mkdir -p /ram
  append_once "$line" /etc/fstab
  sudo install -m 0644 "$DOTFILES_DIR/linux/ram.tmpfiles" /etc/tmpfiles.d/ram.conf
  if ! mountpoint -q /ram; then
    sudo mount /ram || warn "could not mount /ram now; it will mount on next boot"
  fi
  sudo systemd-tmpfiles --create /etc/tmpfiles.d/ram.conf 2>/dev/null || true
  ok "/ram tmpfs ready (32G) — TMPDIR, project RAM copies and the Postgres cluster live here"
}

setup_zram() {
  paru_install zram-generator
  sudo install -m 0644 "$DOTFILES_DIR/linux/zram-generator.conf" /etc/systemd/zram-generator.conf
  sudo install -m 0644 "$DOTFILES_DIR/linux/99-zram.conf" /etc/sysctl.d/99-zram.conf
  sudo sysctl --system >/dev/null 2>&1 || true
  sudo systemctl daemon-reload
  sudo systemctl restart systemd-zram-setup@zram0.service 2>/dev/null || true
  ok "zram swap configured (16G zstd) — keeps a 32G tmpfs from OOM-ing the box"
}

setup_pg_ram() {
  paru_install postgresql
  sudo mkdir -p /etc/postgresql
  sudo install -m 0644 "$DOTFILES_DIR/linux/pg-ram.conf" /etc/postgresql/pg-ram.conf
  sudo install -m 0755 "$DOTFILES_DIR/linux/pg-ram-init.sh" /usr/local/bin/pg-ram-init
  sudo install -m 0644 "$DOTFILES_DIR/linux/pg-ram-init.service" /etc/systemd/system/pg-ram-init.service
  sudo mkdir -p /etc/systemd/system/postgresql.service.d
  sudo install -m 0644 "$DOTFILES_DIR/linux/postgresql-ram.override.conf" \
    /etc/systemd/system/postgresql.service.d/ram.conf
  sudo systemctl daemon-reload
  sudo systemctl enable pg-ram-init.service >/dev/null 2>&1 || true
  sudo systemctl enable postgresql.service >/dev/null 2>&1 || true
  if systemctl is-active --quiet postgresql && sudo test -f /ram/pgdata/PG_VERSION; then
    ok "PostgreSQL already running from /ram/pgdata — leaving it alone"
  else
    sudo systemctl restart pg-ram-init.service || warn "pg-ram-init failed; check 'systemctl status pg-ram-init'"
    sudo systemctl restart postgresql.service || warn "postgresql failed to start; check 'systemctl status postgresql'"
  fi
  ok "PostgreSQL runs from /ram/pgdata (ephemeral, fsync=off, port 5432, role denpatin)"
  info "the cluster is rebuilt empty on every boot — run your migrations (rails db:setup)"
}

setup_thermals() {
  paru_install thermald power-profiles-daemon ananicy-cpp cachyos-ananicy-rules
  sudo systemctl enable --now thermald >/dev/null 2>&1 || warn "could not enable thermald"
  sudo systemctl enable --now power-profiles-daemon >/dev/null 2>&1 || true
  sudo systemctl enable --now ananicy-cpp >/dev/null 2>&1 || warn "could not enable ananicy-cpp"
  ok "thermald + power-profiles-daemon + ananicy-cpp enabled"
}

setup_drivers() {
  log "installing audio, bluetooth and GPU drivers..."
  case "$PROFILE" in
    cachyos)
      paru_install \
        sof-firmware alsa-ucm-conf alsa-utils alsa-firmware \
        pipewire pipewire-alsa pipewire-pulse wireplumber \
        bluez bluez-utils libldac libfreeaptx \
        mesa vulkan-intel intel-media-driver libva-utils
      ;;
    ubuntu)
      apt_install \
        firmware-sof-signed alsa-ucm-conf alsa-utils \
        pipewire pipewire-alsa pipewire-pulse wireplumber \
        bluez libldacbt-enc2 libfreeaptx0 \
        mesa-va-drivers intel-media-va-driver-non-free vainfo \
        || warn "some driver packages unavailable via apt"
      ;;
  esac
  sudo systemctl enable --now bluetooth.service >/dev/null 2>&1 || warn "could not enable bluetooth.service"
  systemctl --user enable --now pipewire pipewire-pulse wireplumber >/dev/null 2>&1 || true
  sudo install -m 0644 "$DOTFILES_DIR/linux/99-trackpoint.rules" /etc/udev/rules.d/99-trackpoint.rules
  sudo udevadm control --reload-rules 2>/dev/null || true
  ok "speakers, mic, bluetooth (LDAC/aptX) and VA-API video decode ready; TrackPoint disabled"
}

install_intel_undervolt() {
  if [ "$CPU_VENDOR" != GenuineIntel ]; then
    info "non-Intel CPU, skipping intel-undervolt"
    return 0
  fi
  if ! have intel-undervolt; then
    log "installing intel-undervolt..."
    case "$PROFILE" in
      cachyos) paru_install intel-undervolt ;;
      ubuntu)
        if apt-cache show intel-undervolt >/dev/null 2>&1; then
          apt_install intel-undervolt
        else
          build_intel_undervolt
        fi
        ;;
    esac
  fi
  have intel-undervolt || {
    warn "intel-undervolt unavailable, skipping power limits"
    return 0
  }
  if ! printf '%s' "$CPU_MODEL" | grep -qiF "$IUV_TUNED_MODEL"; then
    warn "power limits 30/8 22/10 are tuned for $IUV_TUNED_MODEL; detected '${CPU_MODEL:-unknown}'"
    info "intel-undervolt installed but left unconfigured for this CPU"
    return 0
  fi
  configure_intel_undervolt
}

build_intel_undervolt() {
  log "building intel-undervolt from source..."
  apt_install build-essential pkg-config
  local tmp
  tmp="$(mktemp -d)"
  git clone -q https://github.com/kitsunyan/intel-undervolt "$tmp/iuv"
  (cd "$tmp/iuv" && make && sudo make install)
  rm -rf "$tmp"
}

configure_intel_undervolt() {
  local conf=/etc/intel-undervolt.conf
  [ -f "$conf" ] || {
    warn "$conf missing after install, skipping config"
    return 0
  }
  sudo cp -n "$conf" "$conf.dotfiles.bak" 2>/dev/null || true

  if sudo grep -qE '^[[:space:]]*power[[:space:]]+package[[:space:]]+30/8[[:space:]]+22/10' "$conf"; then
    ok "power package limit already 30/8 22/10"
  else
    log "setting 'power package 30/8 22/10'..."
    sudo sed -i -E '/^[[:space:]]*power[[:space:]]+package[[:space:]]+/d' "$conf"
    append_once 'power package 30/8 22/10' "$conf"
  fi

  sudo sed -i -E 's/^([[:space:]]*)daemon[[:space:]]+undervolt:once/\1# daemon undervolt:once/' "$conf"
  sudo sed -i -E 's/^([[:space:]]*)daemon[[:space:]]+tjoffset/\1# daemon tjoffset/' "$conf"
  if sudo grep -qE '^[[:space:]]*#[[:space:]]*daemon[[:space:]]+power\b' "$conf"; then
    sudo sed -i -E 's/^([[:space:]]*)#[[:space:]]*daemon[[:space:]]+power\b/\1daemon power/' "$conf"
  else
    append_once 'daemon power' "$conf"
  fi

  sudo intel-undervolt apply || warn "intel-undervolt apply failed"
  sudo systemctl enable --now intel-undervolt >/dev/null 2>&1 \
    || warn "could not enable intel-undervolt.service"
  ok "power limits applied: PL2 30W/8s, PL1 22W/10s (no thermal throttling, full burst)"
}

native_rebuild() {
  local pkg="$1" tmp
  tmp="$(mktemp -d)"
  if ! (cd "$tmp" && paru -G "$pkg" >/dev/null 2>&1); then
    warn "could not fetch PKGBUILD for $pkg"
    rm -rf "$tmp"
    return 1
  fi
  if (cd "$tmp/$pkg" && makepkg -srifc --noconfirm); then
    ok "$pkg rebuilt natively (-march=native)"
  else
    warn "native rebuild of $pkg failed; the repo version stays installed"
  fi
  rm -rf "$tmp"
}

install_native_rebuilds() {
  log "rebuilding hot tools from source for this exact CPU (-march=native)..."
  info "these are the only daily-driver tools with no x86-64-v3 build in the repos"
  local pkg
  for pkg in starship ${SHELL_CHOICE:+$([ "$SHELL_CHOICE" = fish ] && echo fish)}; do
    native_rebuild "$pkg" || true
  done
}

install_mise() {
  if have mise; then
    MISE_BIN="$(command -v mise)"
  elif [ -x "$HOME/.local/bin/mise" ]; then
    MISE_BIN="$HOME/.local/bin/mise"
  else
    log "installing mise..."
    case "$PROFILE" in
      cachyos) paru_install mise && MISE_BIN="$(command -v mise)" ;;
      *)
        curl -fsSL https://mise.run | sh
        MISE_BIN="$HOME/.local/bin/mise"
        ;;
    esac
  fi
  [ -x "$MISE_BIN" ] || have mise || die "could not install mise"
  [ "$UPGRADE" = 1 ] && "$MISE_BIN" self-update -y >/dev/null 2>&1
  return 0
}

link_dotfiles() {
  log "symlinking configs..."
  mkdir -p "$HOME/.config" "$HOME/.config/mise/conf.d" "$HOME/.ssh" "$HOME/Repos"

  ln -sf "$DOTFILES_DIR/.gitconfig" "$HOME/.gitconfig"
  ln -sf "$DOTFILES_DIR/mise/config.toml" "$HOME/.config/mise/config.toml"

  case "$PROFILE" in
    cachyos)
      ln -sf "$DOTFILES_DIR/mise/cachyos.toml" "$HOME/.config/mise/conf.d/cachyos.toml"
      rm -f "$HOME/.config/mise/conf.d/linux.toml"
      ;;
    ubuntu)
      ln -sf "$DOTFILES_DIR/mise/linux.toml" "$HOME/.config/mise/conf.d/linux.toml"
      rm -f "$HOME/.config/mise/conf.d/cachyos.toml"
      ;;
  esac

  ln -sfn "$DOTFILES_DIR/nvim" "$HOME/.config/nvim"
  ln -sfn "$DOTFILES_DIR/zellij" "$HOME/.config/zellij"
  ln -sf "$DOTFILES_DIR/starship.toml" "$HOME/.config/starship.toml"

  if want_gui; then
    ln -sfn "$DOTFILES_DIR/ghostty" "$HOME/.config/ghostty"
  fi

  if [ "$PROFILE" != macos ]; then
    mkdir -p "$HOME/.cargo"
    ln -sf "$DOTFILES_DIR/cargo/config.toml" "$HOME/.cargo/config.toml"
  fi

  ln -sf "$DOTFILES_DIR/ssh/config" "$HOME/.ssh/config"
  chmod 700 "$HOME/.ssh"
  chmod 600 "$DOTFILES_DIR/ssh/config"

  if [ "$SHELL_CHOICE" = fish ]; then
    mkdir -p "$HOME/.config/fish/functions"
    ln -sf "$DOTFILES_DIR/config.fish" "$HOME/.config/fish/config.fish"
    ln -sf "$DOTFILES_DIR/fish_functions/fish_user_key_bindings.fish" \
      "$HOME/.config/fish/functions/fish_user_key_bindings.fish"
  else
    ln -sf "$DOTFILES_DIR/.zshrc" "$HOME/.zshrc"
    ln -sf "$DOTFILES_DIR/.zshenv" "$HOME/.zshenv"
  fi

  if want_gui; then
    local vscode_user_dir
    if [ "$PROFILE" = macos ]; then
      vscode_user_dir="$HOME/Library/Application Support/Code/User"
    else
      vscode_user_dir="$HOME/.config/Code/User"
    fi
    mkdir -p "$vscode_user_dir"
    ln -sf "$DOTFILES_DIR/vscode/settings.json" "$vscode_user_dir/settings.json"
  fi
}

install_oh_my_zsh() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log "installing oh-my-zsh..."
    RUNZSH=no CHSH=no /bin/sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  fi
  local custom="$HOME/.oh-my-zsh/custom"
  [ -d "$custom/plugins/zsh-autosuggestions" ] \
    || git clone -q https://github.com/zsh-users/zsh-autosuggestions "$custom/plugins/zsh-autosuggestions"
  [ -d "$custom/plugins/zsh-syntax-highlighting" ] \
    || git clone -q https://github.com/zsh-users/zsh-syntax-highlighting "$custom/plugins/zsh-syntax-highlighting"
}

install_languages() {
  log "installing language runtimes and CLI tools via mise..."
  if ! MISE_YES=1 "$MISE_BIN" install; then
    warn "some mise tools failed to install, rerun 'mise install' later"
  fi
  if [ "$UPGRADE" = 1 ]; then
    log "upgrading mise tools..."
    MISE_YES=1 "$MISE_BIN" upgrade 2>/dev/null || true
  fi
  return 0
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

prog_ghostty() {
  have ghostty && return 0
  log "installing ghostty..."
  case "$PROFILE" in
    cachyos) paru_install ghostty ;;
    ubuntu)
      if apt-cache show ghostty >/dev/null 2>&1; then
        apt_install ghostty
      elif sudo add-apt-repository -y ppa:mkasberg/ghostty-ubuntu 2>/dev/null; then
        sudo apt-get update && apt_install ghostty
      else
        local url tmp
        url="$(curl -fsSL https://api.github.com/repos/mkasberg/ghostty-ubuntu/releases/latest \
          | grep -o "https://[^\"]*_amd64_${UBUNTU_CODENAME}\.deb" | head -n1)"
        if [ -n "$url" ]; then
          tmp="$(mktemp -d)"
          curl -fsSL "$url" -o "$tmp/ghostty.deb"
          apt_install "$tmp/ghostty.deb"
          rm -rf "$tmp"
        else
          warn "no ghostty build for ${UBUNTU_CODENAME}, skipping"
        fi
      fi
      ;;
  esac
}

prog_vscode() {
  if have code; then
    install_vscode_extensions
    return 0
  fi
  log "installing vscode..."
  case "$PROFILE" in
    cachyos) paru_install visual-studio-code-bin ;;
    ubuntu)
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor --yes -o /usr/share/keyrings/microsoft.gpg
      echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
        | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
      sudo apt-get update
      apt_install code
      ;;
  esac
  install_vscode_extensions
}

install_vscode_extensions() {
  have code || {
    warn "code not found, skipping vscode extensions"
    return 0
  }
  log "installing vscode extensions..."
  local ext
  while IFS= read -r ext; do
    code --install-extension "$ext" --force >/dev/null 2>&1 || warn "failed: $ext"
  done < <(grep '^vscode "' "$DOTFILES_DIR/Brewfile" | cut -d'"' -f2)
}

prog_brave() {
  have brave-browser || have brave || {
    log "installing brave browser..."
    case "$PROFILE" in
      cachyos) paru_install brave-bin ;;
      ubuntu)
        sudo curl -fsSLo /usr/share/keyrings/brave-browser-archive-keyring.gpg \
          https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg arch=amd64] https://brave-browser-apt-release.s3.brave.com/ stable main" \
          | sudo tee /etc/apt/sources.list.d/brave-browser-release.list >/dev/null
        sudo apt-get update
        apt_install brave-browser
        ;;
    esac
  }
}

prog_ngrok() {
  have ngrok && return 0
  log "installing ngrok..."
  case "$PROFILE" in
    cachyos) paru_install ngrok ;;
    ubuntu)
      curl -fsSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo gpg --dearmor --yes -o /usr/share/keyrings/ngrok.gpg
      echo "deb [signed-by=/usr/share/keyrings/ngrok.gpg] https://ngrok-agent.s3.amazonaws.com bookworm main" \
        | sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null
      sudo apt-get update
      apt_install ngrok
      ;;
  esac
}

prog_rubyfmt() {
  have rubyfmt && [ "$UPGRADE" != 1 ] && return 0
  case "$PROFILE" in
    cachyos)
      paru_install rubyfmt
      return 0
      ;;
  esac
  log "installing rubyfmt..."
  local tag tmp
  tag="$(curl -fsSL https://api.github.com/repos/fables-tales/rubyfmt/releases/latest | grep '"tag_name"' | cut -d'"' -f4)"
  [ -n "$tag" ] || {
    warn "could not resolve rubyfmt release"
    return 0
  }
  tmp="$(mktemp -d)"
  if curl -fsSL "https://github.com/fables-tales/rubyfmt/releases/download/${tag}/rubyfmt-${tag}-Linux-x86_64.tar.gz" -o "$tmp/rubyfmt.tar.gz"; then
    tar xzf "$tmp/rubyfmt.tar.gz" -C "$tmp"
    sudo install "$(find "$tmp" -name 'rubyfmt*' -type f -perm -u+x | head -n1)" /usr/local/bin/rubyfmt
  else
    warn "rubyfmt prebuilt binary not found"
  fi
  rm -rf "$tmp"
}

prog_postgres_plain() {
  have psql && return 0
  log "installing postgresql..."
  case "$PROFILE" in
    ubuntu)
      apt_install postgresql-common
      sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y || true
      sudo apt-get update
      apt_install postgresql
      ;;
  esac
}

prog_pixi() {
  have pixi && return 0
  log "installing pixi..."
  case "$PROFILE" in
    cachyos) paru_install pixi ;;
    ubuntu)
      curl -fsSL https://pixi.sh/install.sh \
        | env PIXI_NO_PATH_UPDATE=1 PIXI_BIN_DIR="$HOME/.local/bin" sh \
        || warn "pixi install failed"
      ;;
  esac
}

prog_ollama() {
  have ollama && [ "$UPGRADE" != 1 ] && return 0
  log "installing ollama..."
  case "$PROFILE" in
    cachyos)
      paru_install ollama
      sudo systemctl enable --now ollama >/dev/null 2>&1 || true
      ;;
    *) curl -fsSL https://ollama.com/install.sh | sh ;;
  esac
}

prog_swi_prolog() {
  have swipl && return 0
  log "installing swi-prolog..."
  case "$PROFILE" in
    cachyos) paru_install swi-prolog ;;
    ubuntu)
      sudo apt-add-repository -y ppa:swi-prolog/stable 2>/dev/null || true
      sudo apt-get update
      apt_install swi-prolog
      ;;
  esac
}

prog_latex() {
  have latexmk && return 0
  log "installing latex (texlive)..."
  case "$PROFILE" in
    cachyos) paru_install texlive-meta biber ;;
    ubuntu)
      apt_install texlive texlive-latex-extra texlive-fonts-extra texlive-bibtex-extra \
        texlive-science texlive-xetex texlive-luatex latexmk biber chktex
      ;;
  esac
}

prog_awscli() {
  have aws && [ "$UPGRADE" != 1 ] && return 0
  log "installing awscli..."
  if [ "$PROFILE" = cachyos ]; then
    paru_install aws-cli-v2
    return 0
  fi
  local tmp
  tmp="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$tmp/awscliv2.zip"
  unzip -q "$tmp/awscliv2.zip" -d "$tmp"
  sudo "$tmp/aws/install" --update
  rm -rf "$tmp"
}

prog_czkawka() {
  have czkawka_cli && return 0
  log "installing czkawka..."
  case "$PROFILE" in
    cachyos) paru_install czkawka-cli ;;
    *) warn "czkawka has no apt package; install via 'cargo install czkawka_cli' if needed" ;;
  esac
}

prog_jetbrains_toolbox() {
  [ -x "$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox" ] && [ "$UPGRADE" != 1 ] && return 0
  log "installing jetbrains toolbox..."
  if [ "$PROFILE" = cachyos ]; then
    paru_install jetbrains-toolbox
    return 0
  fi
  local url tmp
  url="$(curl -fsSL 'https://data.services.jetbrains.com/products/releases?code=TBA&latest=true&type=release' \
    | grep -o 'https://[^"]*jetbrains-toolbox-[^"]*\.tar\.gz' | head -n1)"
  [ -n "$url" ] || {
    warn "could not resolve jetbrains toolbox url"
    return 0
  }
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/tbx.tar.gz"
  tar xzf "$tmp/tbx.tar.gz" -C "$tmp"
  mkdir -p "$HOME/.local/bin"
  install "$tmp"/jetbrains-toolbox-*/jetbrains-toolbox "$HOME/.local/bin/jetbrains-toolbox"
  rm -rf "$tmp"
}

optional_menu_entries() {
  cat <<'EOF'
ngrok|ngrok tunneling|on
rubyfmt|rubyfmt (Ruby formatter)|on
pixi|pixi (conda-forge package/env manager)|on
awscli|AWS CLI v2|on
latex|Full LaTeX (TeX Live) + latexmk/biber/chktex|off
ollama|Ollama (local LLMs)|off
swi_prolog|SWI-Prolog|off
czkawka|czkawka duplicate/space cleaner|off
EOF
  if want_gui; then
    echo "ghostty|Ghostty terminal|on"
    echo "vscode|Visual Studio Code + extensions|on"
    echo "brave|Brave Browser|on"
    echo "jetbrains_toolbox|JetBrains Toolbox|off"
  fi
  if [ "$PROFILE" = cachyos ]; then
    echo "native_rebuilds|Native rebuild of starship (+ fish) for this exact CPU|on"
  else
    echo "postgres|PostgreSQL server|off"
  fi
}

comp_label() {
  local k l
  while IFS='|' read -r k l _; do
    [ "$k" = "$1" ] && {
      echo "$l"
      return 0
    }
  done < <(optional_menu_entries)
  echo "$1"
}

_ver() {
  local c="$1"
  shift
  have "$c" || return 1
  "$c" "$@" 2>/dev/null | head -n1
}

comp_status() {
  case "$1" in
    vscode) _ver code --version ;;
    ghostty) _ver ghostty --version ;;
    brave) _ver brave-browser --version || _ver brave --version ;;
    ngrok) _ver ngrok --version ;;
    rubyfmt) have rubyfmt && echo installed ;;
    pixi) _ver pixi --version ;;
    awscli) _ver aws --version ;;
    latex) _ver latexmk --version ;;
    ollama) _ver ollama --version ;;
    swi_prolog) _ver swipl --version ;;
    czkawka) have czkawka_cli && echo installed ;;
    jetbrains_toolbox) { [ -x "$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox" ] || have jetbrains-toolbox; } && echo installed ;;
    postgres) _ver psql --version ;;
    native_rebuilds) return 1 ;;
    *) return 1 ;;
  esac
}

comp_install() {
  case "$1" in
    vscode) prog_vscode ;;
    ghostty) prog_ghostty ;;
    brave) prog_brave ;;
    ngrok) prog_ngrok ;;
    rubyfmt) prog_rubyfmt ;;
    pixi) prog_pixi ;;
    awscli) prog_awscli ;;
    latex) prog_latex ;;
    ollama) prog_ollama ;;
    swi_prolog) prog_swi_prolog ;;
    czkawka) prog_czkawka ;;
    jetbrains_toolbox) prog_jetbrains_toolbox ;;
    postgres) prog_postgres_plain ;;
    native_rebuilds) install_native_rebuilds ;;
  esac
}

gated_install() {
  local key="$1" label ver
  label="$(comp_label "$key")"
  if ver="$(comp_status "$key" 2>/dev/null)" && [ -n "$ver" ]; then
    ok "$label — already installed ($ver)"
    record_present "$label"
    if [ "$UPGRADE" = 1 ]; then
      confirm "re-run installer to upgrade $label?" n && run_step "$label" comp_install "$key"
    fi
    return 0
  fi
  if confirm "Proceed installing $label?"; then
    run_step "$label" comp_install "$key"
    if [ "$LAST_STEP_RC" -eq 0 ]; then
      record_done "$label"
    else
      record_fail "$label" "see messages above; re-run to retry"
    fi
  else
    info "skipped $label"
    record_skip "$label"
  fi
}

select_optional() {
  local -a keys descs states inst
  local key desc def i

  while IFS='|' read -r key desc def; do
    [ -n "$key" ] || continue
    keys+=("$key")
    descs+=("$desc")
    [ "$def" = on ] && states+=("on") || states+=("off")
    if comp_status "$key" >/dev/null 2>&1; then inst+=("yes"); else inst+=("no"); fi
  done < <(optional_menu_entries)

  if [ "$INTERACTIVE" != 1 ]; then
    for i in "${!keys[@]}"; do
      [ "${states[$i]}" = on ] && SELECTED_OPTIONAL+=("${keys[$i]}")
    done
    return 0
  fi

  while true; do
    printf '\nOptional programs ([x]=will attempt, (installed)=already present):\n'
    for i in "${!keys[@]}"; do
      local tag=''
      [ "${inst[$i]}" = yes ] && tag=' \033[0;32m(installed)\033[0m'
      printf '  %2d) [%s] %b%b\n' "$((i + 1))" \
        "$([ "${states[$i]}" = on ] && echo x || echo ' ')" "${descs[$i]}" "$tag"
    done
    printf '\nToggle by number (e.g. "1 3 5"), "a" all, "n" none, ENTER to accept: '
    local input tok idx
    read -r input </dev/tty || input=""
    case "$input" in
      "") break ;;
      a | A) for i in "${!states[@]}"; do states[i]=on; done ;;
      n | N) for i in "${!states[@]}"; do states[i]=off; done ;;
      *)
        for tok in $input; do
          if [[ "$tok" =~ ^[0-9]+$ ]] && [ "$tok" -ge 1 ] && [ "$tok" -le "${#keys[@]}" ]; then
            idx=$((tok - 1))
            [ "${states[idx]}" = on ] && states[idx]=off || states[idx]=on
          fi
        done
        ;;
    esac
  done

  for i in "${!keys[@]}"; do
    [ "${states[$i]}" = on ] && SELECTED_OPTIONAL+=("${keys[$i]}")
  done
}

print_status() {
  log "status on $PROFILE ($ARCH${ISA_LEVEL:+, x86-64-$ISA_LEVEL}):"
  local tool key label ver
  printf '  shells & core:\n'
  for tool in fish zsh git mise ghostty nvim zellij tmux; do
    if have "$tool"; then ok "$tool"; else miss "$tool"; fi
  done
  printf '  cli tools:\n'
  for tool in bat fd eza rg ugrep zoxide delta jaq jq yq uv bun starship yazi \
    dust duf procs sd fzf just hurl xh xxh heroku ty gh hyperfine sccache ccache \
    cmake typst watchexec broot jless jj syswatch; do
    if have "$tool"; then ok "$tool"; else miss "$tool"; fi
  done
  if [ "$PROFILE" != macos ]; then
    for tool in mold shellcheck; do
      if have "$tool"; then ok "$tool"; else miss "$tool"; fi
    done
    printf '  optional programs:\n'
    while IFS='|' read -r key label _; do
      if ver="$(comp_status "$key" 2>/dev/null)" && [ -n "$ver" ]; then
        ok "$label — $ver"
      else
        miss "$label"
      fi
    done < <(optional_menu_entries)
  else
    printf '  optional programs: managed by Brewfile (brew bundle check)\n'
  fi
}

install_cachyos() {
  tracked_step "cachyos v3 repos" "check network/mirrors, then re-run" setup_cachyos_repos
  tracked_step "native makepkg" "check sudo perms on /etc/makepkg.conf.d" setup_native_makepkg
  tracked_step "base toolchain" "fix pacman mirrors/keyring, then re-run" install_base_cachyos
  tracked_step "v3 cli tools" "run 'paru -S <pkg>' for the failures above" install_cachyos_tools

  want_hw || {
    info "WSL: skipping kernel, drivers, thermals, zram, /ram tmpfs and RAM-Postgres"
    return 0
  }

  tracked_step "BORE-LTO kernel" "run 'paru -S linux-cachyos-bore-lto' manually" install_cachyos_kernel
  tracked_step "drivers (audio/bt/gpu)" "check 'paru -S sof-firmware bluez'" setup_drivers
  tracked_step "thermals" "check 'systemctl status thermald ananicy-cpp'" setup_thermals
  tracked_step "zram swap" "check 'systemctl status systemd-zram-setup@zram0'" setup_zram
  tracked_step "/ram tmpfs" "check /etc/fstab and 'mount /ram'" setup_ram_tmpfs
  tracked_step "postgres in RAM" "check 'systemctl status pg-ram-init postgresql'" setup_pg_ram
  tracked_step "intel-undervolt" "run 'sudo intel-undervolt apply' manually" install_intel_undervolt
}

install_ubuntu() {
  tracked_step "base toolchain" "fix apt sources/network, then re-run" install_base_ubuntu
  if want_hw; then
    tracked_step "drivers (audio/bt/gpu)" "check apt package names" setup_drivers
    tracked_step "intel-undervolt" "run 'sudo intel-undervolt apply' manually" install_intel_undervolt
  else
    info "WSL: skipping drivers and power tuning"
  fi
}

usage() {
  cat <<EOF
Usage: install.sh [--kind gui|cli|wsl] [--shell fish|zsh] [--yes] [--upgrade] [--status]
  --kind     gui = standalone with desktop apps
             cli = standalone, no desktop apps, still tunes kernel/drivers/power
             wsl = no desktop apps, no kernel or hardware tuning
             Asked interactively with no default; auto-set to wsl under WSL and
             to gui on macOS. Required with --yes on a standalone Linux box.
  --shell    Pick shell non-interactively (fish or zsh; default fish).
  --yes,-y   Accept defaults, no prompts.
  --upgrade  Also re-run installers for already-installed non-repo tools.
  --status   Only print what is installed vs missing, then exit.
  -h,--help  Show this help.
EOF
}

print_summary() {
  local joined entry name hint
  printf '\n\033[0;32m==>\033[0m summary (%s)\n' "$PROFILE"
  if [ "${#RESULT_DONE[@]}" -gt 0 ]; then
    joined="$(join_comma "${RESULT_DONE[@]}")"
    printf '  \033[0;32mdone\033[0m (%d): %s\n' "${#RESULT_DONE[@]}" "$joined"
  fi
  if [ "${#RESULT_PRESENT[@]}" -gt 0 ]; then
    joined="$(join_comma "${RESULT_PRESENT[@]}")"
    printf '  already present (%d): %s\n' "${#RESULT_PRESENT[@]}" "$joined"
  fi
  if [ "${#RESULT_SKIP[@]}" -gt 0 ]; then
    joined="$(join_comma "${RESULT_SKIP[@]}")"
    printf '  skipped (%d): %s\n' "${#RESULT_SKIP[@]}" "$joined"
  fi
  if [ "${#RESULT_FAIL[@]}" -gt 0 ]; then
    printf '  \033[0;31mfailed (%d):\033[0m\n' "${#RESULT_FAIL[@]}"
    for entry in "${RESULT_FAIL[@]}"; do
      name="${entry%%$'\t'*}"
      hint="${entry#*$'\t'}"
      printf '    \033[0;31m✗\033[0m %s — %s\n' "$name" "$hint"
    done
  fi
  printf '  system: %s, shell: %s\n' "$KIND" "$SHELL_CHOICE"
  [ "$CONFIGS_LINKED" = 1 ] \
    && printf '  configs: gitconfig, mise, nvim, zellij, starship, cargo, ssh, %s%s\n' \
      "$SHELL_CHOICE" "$(want_gui && printf ', ghostty, vscode')"
  if [ "$PROFILE" = cachyos ] && want_hw; then
    printf '  kernel: %s (reboot to switch to linux-cachyos-bore-lto)\n' "$(uname -r)"
    printf '  RAM workflow: run "ram" inside any project, "unram" to bring it back, "rams" to list\n'
    printf '  postgres: ephemeral cluster in /ram/pgdata on port 5433 (rebuilt empty on every boot)\n'
  fi
  if [ "${#RESULT_FAIL[@]}" -gt 0 ]; then
    printf '  some steps need attention — fix the notes above, then re-run \033[1m./install.sh\033[0m\n'
  else
    printf '  all good — re-run \033[1m./install.sh\033[0m anytime; installed items are detected and skipped.\n'
  fi
  log "system ready."
  info "open a new terminal to start using $SHELL_CHOICE"
}

main() {
  [ "$(id -u)" -ne 0 ] || die "do not run as root"

  local status_only=0
  local -a orig_args=("$@")
  while [ $# -gt 0 ]; do
    case "$1" in
      --kind)
        KIND="${2:-}"
        shift 2
        ;;
      --kind=*)
        KIND="${1#*=}"
        shift
        ;;
      --shell)
        SHELL_CHOICE="${2:-}"
        shift 2
        ;;
      --shell=*)
        SHELL_CHOICE="${1#*=}"
        shift
        ;;
      --yes | -y)
        ASSUME_YES=1
        shift
        ;;
      --upgrade)
        UPGRADE=1
        shift
        ;;
      --status)
        status_only=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) die "unknown argument: $1" ;;
    esac
  done

  [ -t 0 ] && [ "$ASSUME_YES" != 1 ] && INTERACTIVE=1

  log "detecting system..."
  detect_platform

  local self="${BASH_SOURCE[0]:-}"
  if [ ! -f "$DOTFILES_DIR/install.sh" ] || [ -z "$self" ] || [ ! -f "$self" ]; then
    bootstrap_repo ${orig_args[@]+"${orig_args[@]}"}
  fi

  if [ "$status_only" = 1 ]; then
    [ -n "$KIND" ] || KIND=gui
    print_status
    exit 0
  fi

  choose_kind
  choose_shell
  mkdir -p "$HOME/Repos"

  if [ "$PROFILE" = macos ]; then
    install_macos
    install_shell_pkg
    set_default_shell
    [ "$SHELL_CHOICE" = zsh ] && install_oh_my_zsh
    link_dotfiles
    CONFIGS_LINKED=1
    install_mise
    install_languages
    install_python_tools
    log "system ready."
    info "open a new terminal to start using $SHELL_CHOICE"
    return 0
  fi

  print_status

  if [ "$PROFILE" = cachyos ]; then
    setup_paru
  fi

  tracked_step "shell ($SHELL_CHOICE)" "install '$SHELL_CHOICE' manually, then re-run" install_shell_pkg
  run_step "default shell" set_default_shell

  case "$PROFILE" in
    cachyos) install_cachyos ;;
    ubuntu) install_ubuntu ;;
  esac

  if want_gui && [ "$PROFILE" != macos ]; then
    tracked_step "nerd font" "install JetBrainsMono Nerd Font manually" install_nerd_font
  fi

  if [ "$SHELL_CHOICE" = zsh ]; then
    tracked_step "oh-my-zsh" "clone ohmyzsh manually; re-run" install_oh_my_zsh
  fi

  tracked_step "mise" "install mise from https://mise.run; re-run" install_mise
  tracked_step "link dotfiles" "check write perms on ~ and ~/.config; re-run" link_dotfiles
  [ "$LAST_STEP_RC" -eq 0 ] && CONFIGS_LINKED=1

  tracked_step "mise toolchain" "run 'mise install' to see details; re-run" install_languages
  tracked_step "python tooling" "ensure uv is present, then 'uv tool install jupyterlab'" install_python_tools

  select_optional
  if [ "${#SELECTED_OPTIONAL[@]}" -gt 0 ]; then
    log "optional programs:"
    local key
    for key in "${SELECTED_OPTIONAL[@]}"; do
      gated_install "$key"
    done
  fi

  print_summary
}

main "$@"
