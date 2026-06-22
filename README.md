Den's Dotfiles
==============

Single-command, idempotent workstation setup for MacOS and Linux.
`install.sh` detects platform, CPU and architecture, then brings the machine
to a known state. Re-runs never duplicate or break anything already present --
existing items get confirmed and skipped.

Updates continuously in progress~

## My machines

- **MacBook Pro 16"** (2026): Apple M5 Max 3nm SoC, 18 cores (6 S-cores +
  12 P-cores), 18 threads, 16-core NPU, 614GB/s unified memory bandwidth,
  128GB Unified Memory, 2TB Apple SSD, 16.2" Liquid Retina XDR
  (3456 x 2234) 120Hz ProMotion mini-LED
- **ThinkPad X1 Carbon Gen 11** (2023): 13th Gen Intel Core i7-1370P vPro
  28W, 14 cores (6 P-cores + 8 E-cores), 20 threads, 24M cache, max turbo
  5.20 GHz, base 1.90 GHz, Intel Iris Xe 128MB, 64GB LPDDR5X-7500, 2TB
  NVMe SSD, 14" WUXGA (1920 x 1200) IPS

## Supported systems

| OS                | Managers                 | Notes                       |
| ----------------- | ------------------------ | --------------------------- |
| `MacOS`           | `Homebrew` + `mise`      | reference setup, `Brewfile` |
| `CachyOS` (Arch)  | `pacman`/`paru` + `mise` | CPU-opt repos, native build |
| `Ubuntu` 24/26.04 | `apt` + `mise`           | amd64 / arm64               |
| `Oracle`/`RHEL`10 | `dnf`/`yum` + `mise`     | amd64 / arm64               |
| `NixOS` 26.05     | `nix profile` + `mise`   | advisory (declarative) only |

## Quick start

```sh
git clone git@github.com:denpatin/dotfiles.git ~/dotfiles
~/dotfiles/install.sh
```

Flags:

```
--shell fish|zsh   pick shell non-interactively (default fish)
--yes, -y          accept defaults, no prompts
--upgrade          re-run installers for already-installed non-repo tools
--status           print installed vs missing, then exit (Linux only)
```

Linux runs interactively: installed/missing report, then `Proceed installing
X?` per step. Any step is skippable without aborting the rest. Idempotent
throughout -- stopping midway and re-running is safe.

## Shells

Chosen once at start; the whole environment is wired for it.

- `fish` (default) -- `config.fish`, key bindings in `fish_functions/`
- `zsh` -- `.zshrc`, `.zshenv`

Identical aliases, abbreviations, and functions across both. Prompt `starship`,
directory jump `zoxide` (bound to `cd`).

`fzf`, `broot`, `yazi` (`yy`) integrations load when present.

## Packages per OS

- `MacOS` -- `Homebrew` formulae and casks (`Brewfile`), `mise` for runtimes
  and a few CLI tools, `cargo` for the rest; source of truth for GUI apps,
  never migrated
- `Ubuntu`/`Oracle` -- distro packages for system libs and toolchain,
  `mise` for CLI tools and runtimes (latest/LTS, unpinned)
- `CachyOS` -- core CLI from CPU-optimized `pacman` repos, `paru` (AUR) for
  the rest (see CPU optimization)
- `NixOS` -- `nix profile` for packages; LaTeX, default shell and
  `intel-undervolt` surfaced as `configuration.nix` edits, not applied

## Mandatory Tools

> Everywhere, up-front

- Browser / terminal / editor -- `Brave`, `Ghostty`, `Neovim`
- Core CLI -- `git`, `mise`, `uv`, `rv`, `bat`, `fd`, `fzf`, `ripgrep`, `eza`,
  `zoxide`, `git-delta`, `starship`, `just`, `jaq`, `yq`, `zellij`, `yazi`,
  `broot`, `dust`, `duf`, `procs`, `sd`, `hyperfine`, `ugrep`, `watchexec`,
  `sccache`, `qsv`

## Optional Tools

> Only for Linux

`VS Code` + extensions, `LaTeX` (TeX Live) + `Typst`, `pixi`, `syswatch`,
`AWS CLI`, `PostgreSQL`, `Ollama`, `rubyfmt`, `SWI-Prolog`, `ngrok`,
`JetBrains Toolbox`, `czkawka`, and (Intel-only!!) `intel-undervolt`
(power limits `30/8 22/10`)

## Replaced Commands

Modern power for my old muscle memory:

| Command | Tool       |
| ------- | ---------- |
| `cat`   | `bat`      |
| `cd`    | `zoxide`   |
| `df`    | `duf`      |
| `du`    | `dust`     |
| `find`  | `fd`       |
| `grep`  | `ugrep -G` |
| `jq`    | `jaq`      |
| `ls`    | `eza`      |
| `ps`    | `procs`    |
| `top`   | `syswatch` |

NB: `ripgrep` stays separate for ad-hoc fast search, tho.

## Tools by Domain

- Search / nav -- `ripgrep`, `ugrep`, `fd`, `fzf`, `zoxide`, `broot`, `yazi`
- Inspect / diff -- `bat`, `eza`, `git-delta`, `jless`, `jaq`, `yq`, `qsv`,
  `choose`, `grex`
- Run / build -- `just`, `watchexec`, `hyperfine`, `sccache`, `mise`
- System / disk -- `dust`, `duf`, `procs`, `bandwhich`, `czkawka`, `syswatch`
- Metrics -- `scc`
- VCS / multiplex -- `git`, `jujutsu` (so far only combined with `git`),
  `zellij`
- Profiling -- `rbspy`
- API testing -- `xh`, `hurl`, `atac`, `Bruno`
- Typesetting -- `Typst` + TeX Live (`latexmk`, `biber`, `chktex`)

## Languages & Ecosystems

- C (`gcc-16`, `clang` 22) -- C17 (+23)
- C++ (`g++-16`, `clang++` 22) -- C++20 (+23/26)
- Clojure (`Leiningen`, `babashka`)
- Crystal
- Elixir (`mix`)
- Erlang (`rebar`)
- Fortran (`gfortran`, `fpm`)
- Gleam
- Go (+ TinyGo)
- JS/TS (`Node`, `Bun`)
- Julia
- Nim
- Odin
- Prolog (`SWI-Prolog`)
- Python (`uv`)
- Ruby (`rv`)
- Rust (`cargo`)
- Zig

NB: `MacOS`: bare `gcc`/`cc` are Apple `clang`; GNU GCC is the `-16` suffix;
bare `clang` is `Homebrew` `llvm` 22. All route through the `ccache` shim on
`PATH`.

## GUI Apps & Casks

- Dev -- `VS Code`, `Sublime Text`, `OrbStack`, `JetBrains Toolbox`,
  `GitHub Copilot`, `ngrok`, `Postgres.app`, `UTM`, `Bruno`
- Internet / Social / Msgs -- `Brave`, `Slack`, `Telegram`, `Zoom`
- Productivity / system -- `Raycast`, `Rectangle`, `Maccy`, `Stats`,
  `Commander One`, `Proton Pass`, `notunes` (cuz fuck Apple Music),
  `TG Pro`, `Surfshark`
- Media / storage -- `Spotify`, `Google Drive`, `fuse-t`
- Fonts -- `JetBrains Mono`

## CPU Optimizations for CachyOS

CPU arch & micro-arch level (`v2`/`v3`/`v4`) detected from the dynamic loader
and `/proc/cpuinfo`, so nothing about the CPU is hardcoded.

- Official `CachyOS` repos serve the matching `x86-64-vN` build per package
- `makepkg.conf` set to `-march=native -mtune=native`, `ccache`,
  `RUSTFLAGS=-C target-cpu=native` -- AUR builds target the exact CPU
- `~/.cargo/config.toml` (from `cargo/config.toml`) applies `target-cpu=native`
  to every `cargo` / `mise` cargo-backend build
- Generated `~/.config/mise/conf.d/cachyos.toml` disables `mise` prebuilts for
  core tools already from the optimized repos, keeping CPU-tuned binaries first
  on `PATH` (still needs double-sanity-checking, still in progress)

Core daily-drivers and anything compiled locally are built for the running CPU
automatically.

Other distros use generic `mise` prebuiltins -- intentionally no per-tool
source builds cuz no need (?) outside CachyOS (?).

## Per-OS nuances

- `MacOS` -- non-interactive by design, never touches the `Homebrew` setup
- `CachyOS` -- only target that compiles for the exact CPU
- `Ubuntu` / (any) `RHEL` -- `ugrep` best-effort from distro repos; fallbacks
to system `grep` if absent or any errors
- `NixOS` -- LaTeX (`texliveFull`), login shell, `intel-undervolt`
  (`services.undervolt`) surfaced as `configuration.nix` edits
- `intel-undervolt` -- installs only on `GenuineIntel`; AMD / ARM skip it

## Repo Structure

- `install.sh` -- God-mode cross-OS installer
- `Brewfile` -- MacOS's Homebrew formulae and casks
- `mise/config.toml` -- language runtimes (shared)
- `mise/linux.toml` -- `mise` CLIs for Linux
- `cargo/config.toml` -- native CPU rustflags
- `config.fish` -- fish config (aliases, functions, integrations, etc)
- `.zshrc` / `.zshenv` -- zsh config (mainly just a functional mirror of fish)
- `starship.toml` -- prompt
- `zellij/` -- multiplex config
- `ghostty/` -- term config
- `nvim/` -- neovim config
- `vscode/` -- VSCode settings + extension list
- `ssh/` -- SSH client config
- `.gitconfig` -- git config
