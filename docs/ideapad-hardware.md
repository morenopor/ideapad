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
- **Swap:** 8 GB swap file `/swapfile` (in `/etc/fstab`); enlarged from 2 GB on 2026-10-08 after an out-of-memory logout (see [Maintenance](#maintenance))

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
- **Node.js:** 22.22.1 and npm 9.2.0 — both from the Ubuntu archive (`nodejs`, `npm`); NodeSource is **not** used (its leftover repo file is deleted)
- **Gemini CLI:** 0.63.0 — global npm package `@google/gemini-cli` in `/usr/lib/node_modules`
- **Antigravity CLI (`agy`):** 1.3.1 in `~/.local/bin/agy` — self-updates in the background
- **Antigravity (agent manager):** 2.21.1 in `/opt/antigravity` (`antigravity-app`) — tarball install, see [Antigravity 2.x](#antigravity-2x)
- **Antigravity IDE:** 2.5.5 in `/opt/antigravity-ide` (`antigravity-ide`) — tarball install. The old apt package (1.23.2, the last one that repo published) and its repo were removed
- **Visual Studio Code:** 1.141.0 (classic snap)
- **ChatGPT desktop:** 26.1002.52244 — installed from the official amd64 `.deb`, which registers its own apt repo (`chatgpt.sources`), so it updates with apt; executable `/usr/bin/chatgpt`
- **Codex CLI:** 0.161.0 — user-level **standalone** install (`~/.codex/packages/standalone/releases/…`, command linked from `~/.local/bin/codex`), not npm. It does not self-update; `upkeep.sh` runs `codex update` at most once a week (verified working 2026-10-07). To reinstall: `curl -fsSL https://chatgpt.com/codex/install.sh | sh`

### Preferred apps
Same toolset as the iMac ([morenopor/imac](https://github.com/morenopor/imac), section 4), adjusted for Ubuntu 26.04 — `upkeep.sh` installs anything missing:

| Purpose | Tools |
|---|---|
| CLI editor (default `EDITOR`, `editor` alternative, git) | `micro` |
| Files / disk | `eza` (replaces `exa`; aliased as `ll`/`la` — `ls` stays GNU `ls`, because an eza alias broke `ls -lt`), `ncdu`, `tree` |
| Monitoring / system info | `btop`, `htop`, `fastfetch` (replaces `neofetch`, which Ubuntu dropped; aliased as `neofetch`) |
| Networking | `nmap`, `whois`, `netcat-openbsd`, `lynx` |
| Utilities | `tealdeer` (provides `tldr`; replaces the dropped `tldr`/`tldr-hs`), `jq`, `git`, `curl`, `wget`, `rsync` |
| Markdown / code editor | Visual Studio Code as the **classic snap** (`snap install --classic code`), not the old `.deb` |

Shell preferences live in a marked block in `~/.bashrc` (`# >>> ideapad preferences >>>`); `upkeep.sh` rewrites that block when it differs from the script (backup in `~/.bashrc.upkeep-bak`). Ubuntu Studio packages and `easyeffects` from the iMac profile are **not** installed here (this laptop runs stock GNOME).

**No longer used** (removed by `upkeep.sh`, together with their repos): `teamviewer`, `terraform`.

### iPhone / LAN integration
_Verified 2026-10-07._ `upkeep.sh` keeps these installed using their original install method:

| Component | Version | Install method | Purpose |
|---|---|---|---|
| LocalSend | 1.18.2 | **User-level** Flatpak from Flathub (`org.localsend.localsend_app`) | Send files and text between Ubuntu and the iPhone over the LAN |
| GSConnect | 73 (enabled, active) | **User-scoped** GNOME Shell extension (`gsconnect@andyholmes.github.io`) | Integrates with KDE Connect on the iPhone. Do **not** install the `kdeconnect` desktop package alongside it |
| UxPlay | 1.73.2-1 | APT (`uxplay`) | AirPlay screen and audio mirroring from the iPhone |
| avahi-daemon | 0.8-18ubuntu1.1 | APT, service active | mDNS / local service discovery (needed by UxPlay) |

**Custom AirPlay launcher** (created by `upkeep.sh` only if missing; existing files are never overwritten):
- Script: `~/.local/bin/gabe-iphone-airplay`
- Desktop entry: `~/.local/share/applications/gabe-iphone-airplay.desktop` — app name **iPhone AirPlay**
- Receiver name: **Gabe Lenovo**
- Command: `uxplay -n 'Gabe Lenovo' -p 35000 -pin -avdec` — PIN authentication, software video decoding, fixed TCP/UDP ports 35000–35002

**Firewall:** UFW is inactive; no rules were added. If UFW is ever enabled, allow TCP/UDP 35000–35002 and mDNS (UDP 5353) from the LAN for AirPlay, plus LocalSend (TCP/UDP 53317) and GSConnect/KDE Connect (TCP/UDP 1714–1764).

**Still unverified:** actual iPhone pairing and compatibility with iOS 27.2 beta 3. (GSConnect 73 confirmed enabled and active on 2026-10-07.)

### APT sources (`/etc/apt/sources.list.d/`)
| File | Purpose |
|---|---|
| `ubuntu.sources`, `ubuntu-esm-*.sources` | Ubuntu archive + ESM |
| `claude-desktop.sources` | Claude desktop app |
| `chatgpt.sources` | ChatGPT desktop (added by its official `.deb`) |

Release upgrades rename third-party repos to `*.list.disabled` **and** comment out their `deb` lines; `upkeep.sh` re-enables the known ones (currently Claude Desktop and ChatGPT).

## Antigravity 2.x
Google ships Antigravity 2.x on Linux only as tarballs from <https://antigravity.google/download> (pick **linux x64**). It is split into two products:

| Download | Installs to | Command |
|---|---|---|
| `Antigravity.tar.gz` (agent manager app) | `/opt/antigravity` | `antigravity-app` |
| `Antigravity IDE.tar.gz` (editor) | `/opt/antigravity-ide` | `antigravity-ide` |

To install or update: save the tarball(s) in `~/Downloads` and run `upkeep.sh`. It backs up `~/.antigravity` first (2.x does not migrate old conversations/workspaces), installs into `/opt`, fixes `chrome-sandbox`, and creates a launcher. If the old 1.x apt package is still around, the script purges it together with its repo and signing key once the 2.x IDE is installed. Updates are manual: download the new tarball and re-run the script.

## Maintenance
**One command updates and cleans everything:**

```bash
bash scripts/upkeep.sh           # update + clean + summary
bash scripts/upkeep.sh --check   # summary only, changes nothing (use this first when diagnosing)
bash scripts/upkeep.sh --force   # skip the low-memory guard
```

Every maintenance run is logged automatically to `~/.local/state/upkeep/upkeep-<date-time>-<pid>.log` (private: files 600, directory 700; the 10 newest are kept), so there is no need to pipe through `tee`. `--check` creates no log or state at all. Run it as your normal user from the GNOME desktop session (it refuses to run as root, and the GSConnect step talks to GNOME Shell).

Behaviour and exit codes:
- Unknown options are rejected (exit 2); `--help` prints usage. A second run while one is active is refused (exit 3, `flock`).
- **Memory guard (exit 4):** the run refuses to start if less than 2 GB of RAM is available or memory pressure (`/proc/pressure/memory`, avg10) is above 20%, and lists the top memory users. Close apps or pass `--force`. Reason: on 2026-10-08 the desktop session reached ~17 of 18 GB (terminal tabs running agents ~7 GB, Firefox 3.4 GB, gnome-shell 3 GB) with only 2 GB of swap, and `systemd-oomd` killed gnome-shell — which logged the user out and killed the terminal running `upkeep.sh` mid `apt update`. It looks like a reboot but `journalctl -b` shows the same boot; check with `journalctl -b -u systemd-oomd`.
- The sudo ticket is kept alive for the whole run. A step that fails does not stop the rest; failed steps are listed at the end and the script exits **1**. Exception: if `apt update` fails (`APT::Update::Error-Mode=any`, so partial index downloads count as failure) the run stops before `full-upgrade` and cleanup.
- Summary queries that fail print `UNKNOWN (…)` instead of an empty value; they are diagnostics and do not change the exit code. The summary also shows the Secure Boot state (`mokutil --sb-state`).

What it does (idempotent — safe to re-run):
1. Re-enables third-party apt repos disabled by a release upgrade, removes leftover PPAs for older releases, migrates `.list` files to deb822 `.sources`, and de-duplicates repeated entries.
2. `apt full-upgrade`, `snap refresh`, `npm update -g` (keeps Gemini CLI current and reinstalls it if missing), `codex update` at most once a week (Codex CLI standalone install; if Codex is missing the script prints the reinstall command instead of installing the npm package). Removes the apt `.bak` leftovers and the unused NodeSource repo file.
3. Purges old kernels from previous releases (never the running one), lets `autoremove` drop obsolete libraries, `autoclean`; keeps 2 revisions per snap and removes disabled ones; trims the systemd journal to 4 weeks; keeps only the 2 newest `~/antigravity-backup-*` folders. Unused user Flatpak runtimes are removed after the LocalSend update.
4. Installs any missing [preferred apps](#preferred-apps), swaps obsolete tools for their replacements, moves VS Code to the snap, and sets `micro` as the default editor.
   It also keeps the [iPhone / LAN integration](#iphone--lan-integration) baseline: installs missing `uxplay`/`avahi-daemon`/`flatpak`, keeps avahi running, installs/updates LocalSend as a user Flatpak, asks GNOME Shell to install GSConnect if it is missing, reinstalls ChatGPT desktop from the official `.deb` in `~/Downloads` if it is missing (or newer than the installed one; normal updates come through its apt repo), and recreates the AirPlay launcher if it was deleted.
5. Installs/updates Antigravity 2.x from tarballs in `~/Downloads` (skips if unchanged) and removes the old 1.x apt package and repo.
6. Refreshes firmware metadata from LVFS (fwupd) — **report only**, nothing is flashed.
7. Prints a **SUMMARY** block: versions (including Codex CLI, LocalSend, GSConnect version/state, UxPlay, avahi, ChatGPT, UFW status, Secure Boot state, memory/swap/pressure), available firmware updates, pending upgrades, whether a reboot is needed, apt sources, packages with no repo, the log path, and any failed steps.

Notes:
- "Not upgrading yet due to phasing" is normal: Ubuntu rolls some updates out gradually.
- Firmware updates listed in the summary (BIOS, SSD) are applied manually with `fwupdmgr update`, on AC power, after reading the release notes.
- Packages listed under "no repo" need a human decision. As of 2026-10-07 none are expected: `code`, `neofetch` and `tldr` are replaced by the preferred-apps step, and `teamviewer`/`terraform` are removed. `libpcre3`/`policykit-1` may linger while something still depends on them — that is fine.
