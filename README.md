Den's Dotfiles
==============

Single-command, idempotent workstation setup for MacOS, CachyOS and Ubuntu.
`install.sh` detects the profile, CPU and micro-arch level, then brings the machine to a
known state. It **adds and updates, never deletes and never duplicates** -- re-running is
always safe.

## Quick start

From a completely bare system (only `curl` required -- git, shell and everything else get
installed for you):

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/denpatin/dotfiles/HEAD/install.sh)"
```

It installs `git`, clones this repo to `~/dotfiles`, and hands off to the real installer.

If the repo is already cloned:

```sh
~/dotfiles/install.sh
```

Both paths do exactly the same thing and converge on the same state.

Flags:

```
--kind gui|cli|wsl  gui = standalone with desktop apps
                    cli = standalone, no desktop apps, still tunes kernel/drivers/power
                    wsl = no desktop apps, no kernel or hardware tuning
--shell fish|zsh    pick shell non-interactively (default fish)
--yes, -y           accept defaults, no prompts
--upgrade           re-run installers for already-installed non-repo tools
--status            print installed vs missing, then exit
```

`--kind` is the **first question and has no default** -- a wrong silent guess would install
desktop apps on a headless box. It is auto-set to `wsl` under WSL and to `gui` on macOS, and
is required alongside `--yes` on a standalone Linux box.

Order is fixed: distro -> system kind -> shell (installed **and made default first**) ->
package manager -> toolchain -> kernel/tuning -> mise -> symlinks -> tools -> programs.

## Two independent axes

**Distro** (auto-detected) decides how hard things get optimized:

| Distro    | Policy                                                    |
| --------- | --------------------------------------------------------- |
| `macos`   | Homebrew + `mise`; `Brewfile` rules; never touched         |
| `cachyos` | x86-64-v3 repos, native rebuilds, native Ruby              |
| `ubuntu`  | stock kernel, apt + `mise`, no optimization                |

**System kind** (first question; WSL is auto-detected) decides GUI and hardware:

| Kind  | Desktop apps | Kernel / drivers / power | `/ram` + RAM-Postgres |
| ----- | ------------ | ------------------------ | --------------------- |
| `gui` | yes          | yes                      | yes (CachyOS)         |
| `cli` | no           | yes                      | yes (CachyOS)         |
| `wsl` | no           | no                       | no                    |

So a headless CachyOS box still gets every CPU optimization, and CachyOS under WSL still gets
v3 repos and native builds -- just no kernel, drivers or power tuning. Ubuntu stays boring
either way so Vivado never breaks; WSL2's kernel belongs to Windows (`wsl --update`), not to
the distro.

## My machines

- **MacBook Pro 16"** (2026): Apple M5 Max, 18 cores (6 S + 12 P), 40-core GPU,
  128GB unified memory, 2TB SSD
- **ThinkPad X1 Carbon Gen 11** (2023): i7-1370P vPro 28W, 14 cores (6 P + 8 E), 20 threads,
  64GB LPDDR5X-7500, 2TB NVMe

## Shells

Chosen once at start, installed and made the login shell before anything else.
`config.fish` is the **source of truth**; `.zshrc` is a strict mirror -- identical aliases
and functions, one for one.

Every command-replacing alias is guarded by an existence check, so a half-installed system
never loses `cat`, `ls`, `find` or `grep`.

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
| `node`  | `bun`      |
| `ps`    | `procs`    |
| `top`   | `syswatch` |

`ripgrep` stays separate for ad-hoc search.

## Updating

`upd` is the daily path on every OS. On Linux it prints what changed, from which version to
which, and asks before applying -- the native tools already behave like `brew` when you
don't silence them with `-y`:

- `cachyos` -- `paru -Syu` (repos + AUR in one shot), then `mise outdated` + `mise upgrade`,
  then `uv tool upgrade --all`
- `ubuntu`/`wsl` -- `apt update` + `apt list --upgradable` + `apt upgrade`, then the same
  `mise`/`uv` steps
- `macos` -- unchanged `brew` pipeline

Re-running `install.sh` converges to the same state but is not the update path.

## CPU optimization (CachyOS only)

Micro-arch level is read from the dynamic loader, never hardcoded. The i7-1370P reports
`x86-64-v3` (Raptor Lake fuses off AVX-512, so `v4` cannot appear). If it ever reports less
than `v3`, the installer aborts rather than silently using a slower repo.

**Kernel: `linux-cachyos-bore-lto`, prebuilt for x86-64-v3.** BORE + Clang ThinLTO + `-O3` +
1000 Hz + `PREEMPT_FULL`. Nothing is compiled: the repo build already has everything, and a
local kernel build would buy ~0-2% (the kernel barely uses AVX2) while costing half an hour
per point release.

**BORE over EEVDF**: stock `linux-cachyos` defaults to EEVDF. BORE boosts tasks that sleep
and wake often, which is exactly "editor and terminal stay responsive while `make -j20`
saturates all 20 threads". The `-lto` variant means BORE no longer costs the ThinLTO build,
so there is no tradeoff left to make.

Where each tool comes from:

- **x86-64-v3 repos** -- `bat`, `fd`, `ripgrep`, `zoxide`, `yazi`, `zellij`, `just`, `hurl`,
  `xh`, `neovim`, `git-delta`, `dust`, `duf`, `fzf`, `hyperfine`, `jaq`, `jq`, `jless`,
  `jujutsu`, `sccache`, `ccache`, `sd`, `tmux`, `typst`, `uv`, `watchexec`, `broot`, `atac`,
  `ugrep`, `ghostty`, `git`, `cmake`, `mold`, `gcc`, `llvm`, `clang`, `postgresql`
- **Compiled natively via `cargo`** (`target-cpu=native` from `cargo/config.toml`) -- `eza`,
  `procs`, `md-tui`, `syswatch`
- **Natively rebuilt from source** (`paru -G` + tuned makepkg) -- `starship` and `fish`, the
  only hot daily-drivers with no v3 build. Optional menu item.
- **Ruby is compiled from source** with `-march=native` (`compile = true` in
  `mise/cachyos.toml`) -- every rspec run goes through the interpreter, so this is not a
  micro-optimization
- **Left generic on purpose** -- `bun` (rebuilding it is a Zig + JavaScriptCore build measured
  in hours, and it is not CPU-bound)
- **Not available on Linux at all** -- `clean`; `fd <regex> -X rm` does the same thing

`/etc/makepkg.conf.d/99-native.conf` (a drop-in, so `cachyos-settings` cannot overwrite it)
gives every AUR and rebuilt package `-march=native -O3`, LTO, ccache, `target-cpu=native`
and `GOAMD64=v3` for free.

## Thermals (CachyOS + Ubuntu, same ThinkPad)

`intel-undervolt` with `power package 30/8 22/10` -- PL2 30W/8s, PL1 22W/10s.

A 22W sustained cap settles the X1C around 65-75 C, so the chip never reaches its thermal
ceiling and never drops clocks, while the 30W/8s window covers exactly the short compile and
test spikes. `thermald` and `power-profiles-daemon` handle the rest; `ananicy-cpp` +
`cachyos-ananicy-rules` is what keeps VSCode responsive while `-j20` runs.

## RAM workflow (CachyOS)

32GB tmpfs at `/ram`. `TMPDIR=/ram/tmp`, so every compiler temp file, rspec fixture and
node/esbuild scratch already lands in RAM.

Three commands, project-independent, no sudo, run from anywhere inside a project:

```sh
ram      # copy this project into /ram, symlink the original path at it
unram    # sync it back to disk, restore the real directory
rams     # what is in RAM right now, with sizes
```

`ram` copies (never moves): the on-disk `<project>.disk` stays as backing, so a reboot loses
only work since the last sync -- never the repo, never `.git`. It refuses to run if `/ram`
is unmounted or too small, and rolls back cleanly on any rsync failure.

Because the original path becomes a symlink, everything -- `foreman`, `rspec`, `bun`,
`cargo`, `zig`, VSCode -- keeps using the same path and transparently works in RAM.
**Restart long-running processes after `ram`**: anything started earlier still holds the old
directory's inode.

## PostgreSQL in RAM (CachyOS)

The whole cluster lives in `/ram/pgdata` on **port 5433** and is **rebuilt empty on every
boot** by `pg-ram-init.service`. Development and test data are both disposable by design.

`fsync=off`, `full_page_writes=off`, `synchronous_commit=off`, `wal_level=minimal`,
`jit=off`, `max_connections=200` (enough for `parallel_rspec -n 12` plus foreman). Most of
the rspec speedup comes from durability being off, not from tmpfs itself.

Superusers `postgres` and `denpatin`, trust auth on localhost -- so `psql -U postgres -h
localhost -p 5433` and DataGrip both connect with no password. tmpfs is invisible from the
outside: it is an ordinary TCP server on `localhost:5433`.

After a reboot the cluster is empty, so reload it the usual way:

```sh
just slup     # staging dump -> drecreate + drestore into localhost:5433
just ssp      # parallel test DBs + full suite
```

## Languages

All managed by `mise`, identical on every machine:

- Bun, Node (LTS)
- Crystal, Go, Ruby, Rust, Zig (+ `zls`)
- Python via `uv`
- C/C++ via system `clang`/`gcc` (+ `mold` linker, `ccache`)

Gems: `foreman`, `rubocop`, `solargraph`.

## Tools by domain

- Search / nav -- `ripgrep`, `ugrep`, `fd`, `fzf`, `zoxide`, `broot`, `yazi`
- Inspect / diff -- `bat`, `eza`, `git-delta`, `jless`, `jaq`, `yq`, `qsv`, `choose`, `grex`
- Build / run -- `just`, `watchexec`, `hyperfine`, `sccache`, `ccache`, `mold`, `cmake`, `mise`
- System -- `dust`, `duf`, `procs`, `bandwhich`, `syswatch`, `czkawka`
- VCS / multiplex -- `git`, `jujutsu`, `zellij`, `tmux`
- API -- `xh`, `hurl`, `atac`, `ngrok`
- Python -- `uv`, `ty`, `jupyterlab`
- Ruby -- `rubyfmt`, `rbspy`, `foreman`
- Typesetting -- `typst`, TeX Live
- Metrics -- `scc`, `tokei`

## Repo structure

- `install.sh` -- cross-OS installer (bootstrap + 4 profiles)
- `Brewfile` -- MacOS formulae, casks, VSCode extensions
- `config.fish` -- fish config (source of truth)
- `.zshrc` / `.zshenv` -- zsh config (strict mirror of fish)
- `mise/config.toml` -- runtimes + CLI shared by all OSes
- `mise/linux.toml` -- extra CLI for Ubuntu/WSL
- `mise/cachyos.toml` -- CachyOS overlay: disables mise tools covered by v3 repos,
  compiles Ruby natively
- `cargo/config.toml` -- `target-cpu=native` + `mold` linker
- `linux/` -- makepkg drop-in, zram, `/ram` tmpfs, RAM-Postgres units, TrackPoint rule
- `nvim/`, `ghostty/`, `zellij/`, `starship.toml`, `vscode/`, `ssh/`, `.gitconfig`
