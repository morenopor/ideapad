# Lenovo Ideapad Hardware Profile

This document captures the key hardware and software details for the Lenovo Ideapad development laptop (hostname `gabe-ubuntu-laptop`).

> **For agents (Claude, Gemini, etc.):** to update and clean this machine, run [`scripts/upkeep.sh`](../scripts/upkeep.sh). That single script is the maintenance procedure — see [Maintenance](#maintenance). Don't hand the user a series of separate commands; extend the script instead.

## CPU
- **Model:** Intel(R) Core(TM) i5-8250U CPU @ 1.60GHz (8 threads, 4 cores)
- **Architecture:** x86_64 / amd64 — always download **linux x64** builds, never arm64
- **Base/Max Frequency:** 1.60 GHz base, up to 3.40 GHz boost
- **Virtualization:** Intel VT-x
- **Instruction Extensions:** SSE up to SSE4.2, AVX, AVX2, AES, FMA, BMI1/BMI2, and more (see `Flags`)
- **Caches:**
  - L1d: 128 KiB (4x 32 KiB per core)
  - L1i: 128 KiB (4x 32 KiB per core)
  - L2: 1 MiB (4x 256 KiB per core)
  - L3: 6 MiB shared
- **Mitigations:** CPU microcode mitigations in place for vulnerabilities including Spectre, Meltdown, L1TF, MDS, Retbleed, and more.

## Memory
- **Installed Modules:** 4 GB + 16 GB (total 20 GB; `free -h` reports ~18 GiB usable)

## Graphics
- **Integrated GPU:** Intel UHD Graphics 620 (i915 driver)
- **Discrete GPU:** NVIDIA GeForce GTX 1050 Mobile (nvidia driver 580.178.04, from the Ubuntu archive)

## Storage
- **NVMe SSD:** Kingston A2000 500 GB (model `KINGSTON SA2000M8500G`)
- **HDD:** Seagate ST2000LX001-1RG1 2 TB (512e / 4K physical sectors)

## Networking
- **Wireless:** Qualcomm Atheros QCA9377 802.11ac (ath10k_pci driver)

## Software
_Last verified: 2026-10-07_

- **Distribution:** Ubuntu 26.04.1 LTS (Resolute Raccoon), upgraded from 24.04 (Noble); GNOME 50 on Wayland
- **Kernel:** 7.0.0-38-generic
- **Node.js:** 22.22.1 and npm 9.2.0 — both from the Ubuntu archive (`nodejs`, `npm`); NodeSource is **not** used
- **Gemini CLI:** 0.63.0 — global npm package `@google/gemini-cli` in `/usr/lib/node_modules`
- **Antigravity CLI (`agy`):** 1.3.1 in `~/.local/bin/agy` — self-updates in the background
- **Antigravity IDE:** 1.23.2 via apt (package `antigravity`). This is the **last** version the apt repo will ever publish; 2.x is tarball-only (see below)

### Preferred apps
Same toolset as the iMac ([morenopor/imac](https://github.com/morenopor/imac), section 4), adjusted for Ubuntu 26.04 — `upkeep.sh` installs anything missing:

| Purpose | Tools |
|---|---|
| CLI editor (default `EDITOR`, `editor` alternative, git) | `micro` |
| Files / disk | `eza` (replaces `exa`; aliased as `ls`/`ll`/`la`), `ncdu`, `tree` |
| Monitoring / system info | `btop`, `htop`, `fastfetch` (replaces `neofetch`, which Ubuntu dropped; aliased as `neofetch`) |
| Networking | `nmap`, `whois`, `netcat-openbsd`, `lynx` |
| Utilities | `tealdeer` (provides `tldr`; replaces the dropped `tldr`/`tldr-hs`), `jq`, `git`, `curl`, `wget`, `rsync` |
| Markdown / code editor | Visual Studio Code as the **classic snap** (`snap install --classic code`), not the old `.deb` |

Shell preferences live in a marked block in `~/.bashrc` (`# >>> ideapad preferences >>>`). Ubuntu Studio packages and `easyeffects` from the iMac profile are **not** installed here (this laptop runs stock GNOME).

**No longer used** (removed by `upkeep.sh`, together with their repos): `teamviewer`, `terraform`.

### APT sources (`/etc/apt/sources.list.d/`)
| File | Purpose |
|---|---|
| `ubuntu.sources`, `ubuntu-esm-*.sources` | Ubuntu archive + ESM |
| `antigravity.sources` | Antigravity IDE 1.x (frozen at 1.23.2) |
| `claude-desktop.sources` | Claude desktop app |
| `nodesource.list.disabled` | Not used; keep disabled to avoid mixing Node builds |

Release upgrades rename third-party repos to `*.list.disabled` **and** comment out their `deb` lines; `upkeep.sh` re-enables the known ones.

## Antigravity 2.x
Google ships Antigravity 2.x on Linux only as tarballs from <https://antigravity.google/download> (pick **linux x64**). It is split into two products:

| Download | Installs to | Command |
|---|---|---|
| `Antigravity.tar.gz` (agent manager app) | `/opt/antigravity` | `antigravity-app` |
| `Antigravity IDE.tar.gz` (editor) | `/opt/antigravity-ide` | `antigravity-ide` |

To install or update: save the tarball(s) in `~/Downloads` and run `upkeep.sh`. It backs up `~/.antigravity` first (2.x does not migrate old conversations/workspaces), installs into `/opt`, fixes `chrome-sandbox`, and creates a launcher. Once 2.x is confirmed working, remove the 1.x apt package with `sudo apt remove antigravity` and delete `antigravity.sources`.

## Maintenance
**One command updates and cleans everything:**

```bash
bash scripts/upkeep.sh 2>&1 | tee ~/upkeep-$(date +%F).log
```

What it does (idempotent — safe to re-run):
1. Re-enables third-party apt repos disabled by a release upgrade, removes leftover PPAs for older releases, migrates `.list` files to deb822 `.sources`, and de-duplicates repeated entries.
2. `apt full-upgrade`, `snap refresh`, `npm update -g`.
3. Purges old kernels from previous releases (never the running one), lets `autoremove` drop obsolete libraries, `autoclean`.
4. Installs any missing [preferred apps](#preferred-apps), swaps obsolete tools for their replacements, moves VS Code to the snap, and sets `micro` as the default editor.
5. Installs/updates Antigravity 2.x from tarballs in `~/Downloads` (skips if unchanged).
6. Prints a **SUMMARY** block: versions, pending upgrades, whether a reboot is needed, apt sources, and packages with no repo.

Notes:
- "Not upgrading yet due to phasing" is normal: Ubuntu rolls some updates out gradually.
- Packages listed under "no repo" need a human decision. As of 2026-10-07 none are expected: `code`, `neofetch` and `tldr` are replaced by the preferred-apps step, and `teamviewer`/`terraform` are removed. `libpcre3`/`policykit-1` may linger while something still depends on them — that is fine.
