#!/usr/bin/env bash
# upkeep.sh — update and clean the Lenovo Ideapad (Ubuntu 26.04 LTS).
# Maintains the existing update, cleanup and configuration policy. Review changes before running.
#
# Usage:
#   bash scripts/upkeep.sh           # update + clean + summary (log saved to ~/.local/state/upkeep/, last 10 kept)
#   bash scripts/upkeep.sh --check   # summary only, changes nothing
#
# Optional: drop the Antigravity tarballs in ~/Downloads before running
#   - Antigravity.tar.gz      (Antigravity 2.x agent app)  -> /opt/antigravity      (cmd: antigravity-app)
#   - Antigravity IDE.tar.gz  (Antigravity IDE 2.x)        -> /opt/antigravity-ide  (cmd: antigravity-ide)
# Always pick the linux x64 build (this laptop is amd64). A tarball is only reinstalled if it changed.
set -u
CHECK=0
usage(){ printf '%s\n' 'Usage: bash scripts/upkeep.sh [--check | --help]'; }
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=1;;
    --help|-h) usage; exit 0;;
    *) printf 'Unknown option: %s\n' "$arg" >&2; usage >&2; exit 2;;
  esac
done
(( EUID != 0 )) || { echo 'Run as your desktop user, not root.' >&2; exit 2; }
SL=/etc/apt/sources.list.d
STATE=~/.local/state/upkeep
LOG='not created (--check)'
FAILED=()
say(){ printf '\n=== %s ===\n' "$*"; }
run(){
  local rc
  if "$@"; then return 0
  else rc=$?; FAILED+=("$* (exit $rc)"); printf '!! FAILED: %s (exit %s)\n' "$*" "$rc"; return "$rc"; fi
}
finish(){
  if (( ${#FAILED[@]} )); then
    printf '%s\n' '-- FAILED steps:'; printf '   %s\n' "${FAILED[@]}"; return 1
  fi
  echo '-- maintenance steps OK; review UNKNOWN diagnostics separately'
}
if [ "$CHECK" -eq 0 ]; then
# Private state/log files (600/700). The umask is scoped to a subshell on purpose: a global
# umask 077 would be inherited by sudo/apt/tar and leave /opt apps and apt sources unreadable.
LOG="$STATE/upkeep-$(date +%F-%H%M%S)-$$.log"
( umask 077; mkdir -p "$STATE" && : > "$STATE/upkeep.lock" && : > "$LOG" ) || exit 1
exec 9>>"$STATE/upkeep.lock" || exit 1
flock -n 9 || { echo 'Another upkeep run is active.' >&2; exit 3; }
exec > >(tee -a "$LOG") 2>&1
# Rotate only during maintenance, never during --check.
mapfile -d '' -t logs < <(find "$STATE" -maxdepth 1 -type f -name 'upkeep-*.log' -printf '%T@ %p\0' | sort -zrn)
for entry in "${logs[@]:10}"; do run rm -f -- "${entry#* }" || :; done
sudo -v || exit 1
( while kill -0 $$ 2>/dev/null; do sudo -n true || exit; sleep 50; done ) 2>/dev/null &
KEEPALIVE=$!
trap 'kill "$KEEPALIVE" 2>/dev/null || :' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

say "APT sources"
# Ubuntu disables third-party repos on release upgrades: re-enable known ones.
for name in claude-desktop chatgpt; do
  if [ -f "$SL/$name.list.disabled" ]; then
    run sudo mv "$SL/$name.list.disabled" "$SL/$name.list"
    run sudo sed -i 's/^#\s*deb /deb /' "$SL/$name.list"
    echo "re-enabled $name"
  fi
done
# Leftover PPA for an older release (e.g. jammy) — drop it unless the NVIDIA driver comes from it.
for f in "$SL"/graphics-drivers-ubuntu-ppa-*.sources; do
  [ -e "$f" ] || continue
  case "$f" in *"$(lsb_release -cs)"*) continue;; esac
  if apt-cache policy 'nvidia-driver-*' 2>/dev/null | grep -q launchpad; then
    echo "KEEP $f (NVIDIA driver installed from PPA)"
  else run sudo rm "$f"; echo "removed $f"; fi
done
# Convert any remaining one-line .list files to deb822 .sources.
ls "$SL"/*.list >/dev/null 2>&1 && run sudo apt -y modernize-sources
# Full-stanza equality only: identical URI with different suites is valid.
for f in "$SL"/*.sources; do
  [ -f "$f" ] || continue
  awk 'BEGIN{RS=""} seen[$0]++{d=1} END{exit !d}' "$f" 2>/dev/null || continue  # no duplicate stanza: leave file untouched
  tmp=$(mktemp) || { FAILED+=("APT dedup temporary file"); continue; }
  if awk 'BEGIN{RS="";ORS="\n\n"} !seen[$0]++' "$f" > "$tmp"; then
    if ! cmp -s "$f" "$tmp"; then
      if run sudo cp "$f" "$f.dup.bak"; then run sudo cp "$tmp" "$f"; fi
    fi
  else FAILED+=("read APT sources $f"); fi
  run rm -f -- "$tmp"
done

say "System update"
# Do not upgrade against failed/partially downloaded indices.
if ! run sudo apt -o APT::Update::Error-Mode=any update; then
  finish; exit 1
fi
run sudo DEBIAN_FRONTEND=noninteractive apt -y full-upgrade
run sudo snap refresh
command -v npm >/dev/null && run sudo npm update -g
# Gemini CLI: global npm package (kept current by the npm update above).
command -v gemini >/dev/null || run sudo npm install -g @google/gemini-cli
# Codex CLI: user-level standalone install (~/.codex/packages/standalone, command in ~/.local/bin). It does not
# self-update, so ask it to (at most once a week: it re-downloads even when current); never install the npm package on top of it.
if command -v codex >/dev/null; then
  if [ -z "$(find "$STATE/codex-update.stamp" -mtime -7 2>/dev/null)" ]; then
    if codex update </dev/null; then run touch "$STATE/codex-update.stamp"
    else FAILED+=("codex update"); echo "!! codex update failed; re-run: curl -fsSL https://chatgpt.com/codex/install.sh | sh"; fi
  else echo "codex update skipped (ran in the last 7 days)"; fi
else
  echo "Codex CLI missing: reinstall with: curl -fsSL https://chatgpt.com/codex/install.sh | sh"
fi
# Backups left by modernize-sources / de-duplication are no longer needed once apt update has succeeded.
run sudo rm -f "$SL"/*.list.bak "$SL"/*.dup.bak
# NodeSource is not used (Node comes from the Ubuntu archive).
run sudo rm -f "$SL"/nodesource.*

say "Cleanup"
# Old kernels left from previous releases (no longer in any repo); never touches the running one.
OLDK=$(apt list '?narrow(?installed, ?obsolete, ?name(^linux-))' 2>/dev/null | cut -d/ -f1 | grep -v Listing | grep -v -- "$(uname -r)")
[ -n "$OLDK" ] && run sudo apt -y purge $OLDK
# Obsolete libraries / transitional packages: mark as auto so autoremove drops them only if nothing needs them.
OLDLIB=$(apt list '?narrow(?installed, ?obsolete, ?or(?name(^lib), ?name(^policykit-1$)))' 2>/dev/null | cut -d/ -f1 | grep -v Listing)
[ -n "$OLDLIB" ] && run sudo apt-mark auto $OLDLIB >/dev/null
run sudo apt -y autoremove --purge
run sudo apt -y autoclean
# Snap keeps old revisions around: keep 2 per snap and drop the disabled ones.
run sudo snap set system refresh.retain=2
if SNAP_ALL=$(run snap list --all); then
  while read -r n r; do
    [ -n "$n" ] && run sudo snap remove "$n" --revision="$r"
  done < <(printf '%s\n' "$SNAP_ALL" | awk '/disabled/{print $1, $3}')
else FAILED+=("snap list --all"); fi
# System journal: keep 4 weeks.
run sudo journalctl --vacuum-time=4weeks
# Antigravity data backups made before tarball installs: keep the 2 newest.
mapfile -d '' -t backups < <(find "$HOME" -maxdepth 1 -type d -name 'antigravity-backup-*' -printf '%T@ %p\0' | sort -zrn)
for entry in "${backups[@]:2}"; do run rm -rf -- "${entry#* }"; done

say "Preferred apps (same toolset as the iMac)"
# CLI toolset. Ubuntu dropped exa/neofetch/tldr: eza, fastfetch and tealdeer replace them.
APPS="micro eza ncdu tree btop htop fastfetch nmap whois netcat-openbsd lynx tealdeer jq git curl wget rsync"
MISSING=$(for p in $APPS; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "ok installed" || echo "$p"; done)
# Remove the obsolete predecessors first (tealdeer conflicts with the old tldr packages).
installed(){ dpkg-query -W -f='${Package} ${Status}\n' "$@" 2>/dev/null | awk '/ ok installed$/{print $1}'; }
OLDTOOLS=$(installed neofetch tldr tldr-hs exa)
[ -n "$OLDTOOLS" ] && run sudo apt -y purge $OLDTOOLS
if [ -n "$MISSING" ]; then run sudo apt -y install $MISSING; else echo "all CLI tools present"; fi
command -v tldr >/dev/null && tldr --update >/dev/null 2>&1
# VS Code: preferred as the classic snap (the old .deb has no repo and stopped updating).
if dpkg-query -W -f='${Status}' code 2>/dev/null | grep -q "ok installed"; then run sudo apt -y purge code; fi
snap list code >/dev/null 2>&1 || run sudo snap install --classic code
# micro is the default editor (terminal, sudoedit, git).
run sudo update-alternatives --set editor /usr/bin/micro >/dev/null 2>&1
run git config --global core.editor micro
# Apps no longer used on this laptop: remove them and their repos.
UNWANTED=$(installed teamviewer terraform)
[ -n "$UNWANTED" ] && run sudo apt -y purge $UNWANTED && run sudo apt -y autoremove --purge
run sudo rm -f "$SL"/hashicorp.* "$SL"/teamviewer*
BRC=~/.bashrc; MARK="# >>> ideapad preferences >>>"
if ! grep -qF "$MARK" "$BRC"; then
  run cat >> "$BRC" <<'RC'
# >>> ideapad preferences >>>
export EDITOR=micro VISUAL=micro
alias ls='eza --group-directories-first'
alias ll='eza -lh --git --group-directories-first'
alias la='eza -lah --git --group-directories-first'
alias neofetch='fastfetch'
# <<< ideapad preferences <<<
RC
  echo "preferences added to ~/.bashrc (open a new terminal)"
fi

say "iPhone / LAN integration"
# APT: UxPlay (AirPlay receiver), avahi-daemon (mDNS discovery, required by UxPlay), flatpak (for LocalSend).
LANPKGS="uxplay avahi-daemon flatpak"
LANMISSING=$(for p in $LANPKGS; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "ok installed" || echo "$p"; done)
[ -n "$LANMISSING" ] && run sudo apt -y install $LANMISSING
systemctl is-active --quiet avahi-daemon || run sudo systemctl enable --now avahi-daemon
# LocalSend: user-level Flatpak from Flathub (never system-wide).
run flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak info --user org.localsend.localsend_app >/dev/null 2>&1 || run flatpak install --user -y flathub org.localsend.localsend_app
run flatpak update --user -y --noninteractive
run flatpak uninstall --user --unused -y --noninteractive
# GSConnect: user-scoped GNOME Shell extension (talks to KDE Connect on the iPhone). Do NOT install the kdeconnect desktop package.
GSC=gsconnect@andyholmes.github.io
if ! gnome-extensions info "$GSC" >/dev/null 2>&1; then
  echo "GSConnect missing: GNOME Shell will ask you to confirm the install from extensions.gnome.org"
  run gdbus call --session --dest org.gnome.Shell.Extensions --object-path /org/gnome/Shell/Extensions \
    --method org.gnome.Shell.Extensions.InstallRemoteExtension "$GSC" >/dev/null 2>&1 \
    || echo "could not reach GNOME Shell (run this from a desktop session)"
fi
dpkg-query -W -f='${Status}' kdeconnect 2>/dev/null | grep -q "ok installed" && echo "WARNING: kdeconnect package is installed and conflicts with GSConnect"
# ChatGPT desktop: official amd64 .deb (it adds chatgpt.sources, so routine updates come via apt). Reinstalls from ~/Downloads if missing or older.
CGDEB=$(find ~/Downloads -maxdepth 1 -iname 'chatgpt*_amd64.deb' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
CGPKG=$(dpkg -S /usr/bin/chatgpt 2>/dev/null | cut -d: -f1)
if [ -n "$CGDEB" ]; then
  NEWV=$(dpkg-deb -f "$CGDEB" Version); CURV=$([ -n "$CGPKG" ] && dpkg-query -W -f='${Version}' "$CGPKG")
  if [ -z "$CURV" ] || dpkg --compare-versions "$NEWV" gt "$CURV"; then run sudo apt -y install "$CGDEB"; fi
elif [ -z "$CGPKG" ]; then echo "ChatGPT desktop missing: download the official amd64 .deb to ~/Downloads and re-run"; fi
# Custom AirPlay launcher ("iPhone AirPlay" -> receiver "Gabe Lenovo"). Created only if missing; existing files are kept as-is.
run mkdir -p ~/.local/bin ~/.local/share/applications
if [ ! -e ~/.local/bin/gabe-iphone-airplay ]; then
  run cat > ~/.local/bin/gabe-iphone-airplay <<'AIR'
#!/usr/bin/env bash
# AirPlay receiver for the iPhone: PIN pairing, software video decoding, fixed TCP/UDP ports 35000-35002.
exec uxplay -n 'Gabe Lenovo' -p 35000 -pin -avdec "$@"
AIR
  run chmod +x ~/.local/bin/gabe-iphone-airplay; echo "created ~/.local/bin/gabe-iphone-airplay"
fi
if [ ! -e ~/.local/share/applications/gabe-iphone-airplay.desktop ]; then
  run cat > ~/.local/share/applications/gabe-iphone-airplay.desktop <<DESK
[Desktop Entry]
Name=iPhone AirPlay
Comment=Receive AirPlay screen and audio from the iPhone (UxPlay)
Exec=$HOME/.local/bin/gabe-iphone-airplay
Icon=video-display
Terminal=false
Type=Application
Categories=AudioVideo;Network;
DESK
  run update-desktop-database ~/.local/share/applications 2>/dev/null; echo "created iPhone AirPlay launcher"
fi

install_tarball(){ # $1=tarball $2=dest $3=command $4=desktop-name
  local tb="$1" dest="$2" cmd="$3" label="$4" sum t s bin icon
  sum=$(sha256sum "$tb") || return 1; sum=${sum%% *}
  if [ "$(cat "$dest/.tarball.sha256" 2>/dev/null)" = "$sum" ]; then echo "$label already up to date"; return; fi
  [ -d ~/.antigravity ] && [ ! -d "$HOME/antigravity-backup-$(date +%F)" ] && { cp -a ~/.antigravity "$HOME/antigravity-backup-$(date +%F)" || return 1; }
  t=$(mktemp -d) || return 1
  if ! tar -xzf "$tb" -C "$t"; then rm -rf -- "$t"; return 1; fi
  s="$t"
  local entries=()
  mapfile -d '' -t entries < <(find "$t" -mindepth 1 -maxdepth 1 -print0)
  if (( ${#entries[@]} == 1 )) && [ -d "${entries[0]}" ]; then s="${entries[0]}"; fi
  bin=$(find "$s" -maxdepth 2 -type f -executable -iname 'antigravity*' ! -name '*.so*' -print -quit)
  if [ -z "$bin" ]; then echo "$label: no executable in archive"; rm -rf -- "$t"; return 1; fi
  run sudo rm -rf "$dest" && run sudo mkdir -p "$dest" && run sudo cp -a "$s"/. "$dest"/ && rm -rf "$t" || return 1
  [ -f "$dest/chrome-sandbox" ] && run sudo chown root:root "$dest/chrome-sandbox" && run sudo chmod 4755 "$dest/chrome-sandbox"
  bin=$(find "$dest" -maxdepth 2 -type f -executable -iname 'antigravity*' ! -name '*.so*' | head -1)
  icon=$(find "$dest" -iname '*.png' | grep -i -m1 -E 'antigravity|code|icon')
  if [ -z "$bin" ]; then echo "$label: executable not found, contents:"; ls "$dest"; return 1; fi
  run sudo ln -sf "$bin" "/usr/local/bin/$cmd" || return 1
  mkdir -p ~/.local/share/applications
  run cat > ~/.local/share/applications/$cmd.desktop <<DESK
[Desktop Entry]
Name=$label
Exec=/usr/local/bin/$cmd %F
Icon=${icon:-utilities-terminal}
Type=Application
Categories=Development;IDE;
DESK
  run update-desktop-database ~/.local/share/applications 2>/dev/null
  if ! echo "$sum" | sudo tee "$dest/.tarball.sha256" >/dev/null; then return 1; fi
  echo "$label installed: $bin"
}

say "Antigravity 2.x (tarballs)"
AG=$(find ~/Downloads -maxdepth 1 -iname 'antigravity*.tar.gz' ! -iname '*ide*' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
IDE=$(find ~/Downloads -maxdepth 1 -iname 'antigravity*ide*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
if [ -n "$AG" ]; then run install_tarball "$AG" /opt/antigravity antigravity-app "Antigravity"; else echo "no Antigravity.tar.gz in ~/Downloads"; fi
if [ -n "$IDE" ]; then run install_tarball "$IDE" /opt/antigravity-ide antigravity-ide "Antigravity IDE"; else echo "no 'Antigravity IDE.tar.gz' in ~/Downloads"; fi
# Antigravity 1.x came from an apt repo that stopped at 1.23.2; once the 2.x IDE is in /opt, drop the old package and its repo.
if [ -x /opt/antigravity-ide/antigravity-ide ] && dpkg-query -W -f='${Status}' antigravity 2>/dev/null | grep -q "ok installed"; then
  run sudo apt -y purge antigravity
fi
[ -x /opt/antigravity-ide/antigravity-ide ] && run sudo rm -f "$SL"/antigravity.* /etc/apt/keyrings/antigravity-repo-key.gpg
command -v agy >/dev/null || echo "agy CLI missing: curl -fsSL https://antigravity.google/cli/install.sh | bash"

say "Firmware (report only)"
command -v fwupdmgr >/dev/null && run fwupdmgr refresh --force
fi  # end of changes (skipped with --check)

ver(){ # Antigravity product version: IDE -> product.json ideVersion; agent app -> package.json inside app.asar
  local d="$1" v=""
  v=$(grep -oE '"ideVersion": *"[^"]+"' "$d/resources/app/product.json" 2>/dev/null | cut -d'"' -f4)
  [ -z "$v" ] && [ -f "$d/resources/app.asar" ] && v=$(node -e 'const fs=require("fs"),b=fs.readFileSync(process.argv[1]),h=JSON.parse(b.slice(16,16+b.readUInt32LE(12)).toString()),e=h.files["package.json"],o=8+b.readUInt32LE(4)+Number(e.offset);console.log(JSON.parse(b.slice(o,o+e.size)).version)' "$d/resources/app.asar" 2>/dev/null)
  [ -z "$v" ] && v=$(grep -m1 -oE '"version": *"[^"]+"' "$d/resources/app/package.json" 2>/dev/null | cut -d'"' -f4)
  echo "${v:-n/a}"
}
# Each query distinguishes failure/empty output from an actual result.
query(){
  local label="$1" value rc; shift
  if value=$(timeout 30 "$@" 2>&1); then
    if [ -n "$value" ]; then printf '%-17s %s\n' "$label:" "$value"
    else printf '%-17s UNKNOWN (empty response)\n' "$label:"; fi
  else rc=$?; printf '%-17s UNKNOWN (exit %s): %s\n' "$label:" "$rc" "$value"; fi
}
say "SUMMARY"
query ubuntu lsb_release -ds
query kernel uname -r
query gemini gemini --version
if (( CHECK )); then printf '%-17s %s\n' 'agy:' 'not queried in --check (may self-update)'; else query agy agy --version; fi
query codex bash -o pipefail -c 'v=$(codex --version | head -1) && echo "$v [$(readlink -f "$(command -v codex)")]"'
printf '%-17s %s\n' 'antigravity:' "$(ver /opt/antigravity)"
printf '%-17s %s\n' 'antigravity-ide:' "$(ver /opt/antigravity-ide)"
query node node -v
query npm npm -v
query vscode bash -o pipefail -c 'code --version | head -1'
query editor readlink -f /usr/bin/editor
query localsend bash -o pipefail -c "flatpak info --user org.localsend.localsend_app | awk -F': *' '/Version/{print \$2}'"
query gsconnect bash -o pipefail -c "gnome-extensions info gsconnect@andyholmes.github.io | grep -E 'Version|Enabled|State' | sed 's/^ *//' | paste -sd' ' -"
query uxplay dpkg-query -W '-f=${Version}\n' uxplay
query avahi bash -c 'v=$(dpkg-query -W -f="\${Version}" avahi-daemon) && echo "$v ($(systemctl is-active avahi-daemon 2>/dev/null))"'
CGP=$(dpkg -S /usr/bin/chatgpt 2>/dev/null | cut -d: -f1)
if [ -n "$CGP" ]; then query chatgpt dpkg-query -W '-f=${Version}\n' "$CGP"; else printf '%-17s %s\n' 'chatgpt:' 'UNKNOWN (package not found)'; fi
query ufw bash -o pipefail -c 'sudo -n ufw status | head -1'
query secure-boot mokutil --sb-state
FW_JSON=$(timeout 30 fwupdmgr get-updates --json 2>/dev/null); rc=$?
if [ "$rc" -eq 2 ]; then printf '%-17s %s\n' 'firmware:' 'no updates available'
elif [ "$rc" -eq 0 ]; then
  if FW=$(printf '%s' "$FW_JSON" | jq -er '
    if (.Devices|type) != "array" then error("missing Devices array")
    else [.Devices[]? | select((.Releases // [])|length > 0) |
      "\(.Name) \(.Version) -> \(.Releases[0].Version)"] |
      if length == 0 then "no updates in available metadata" else join("\n") end end' 2>/dev/null); then
    echo 'firmware:'
    while IFS= read -r line; do printf '  %s\n' "$line"; done <<< "$FW"
  else printf '%-17s %s\n' 'firmware:' 'UNKNOWN (invalid JSON or jq unavailable)'; fi
else printf '%-17s UNKNOWN (fwupd exit %s)\n' 'firmware:' "$rc"; fi
query nvidia nvidia-smi --query-gpu=driver_version --format=csv,noheader
printf '%-17s %s\n' 'pending upgrades:' "$(apt list --upgradable 2>/dev/null | grep -c upgradable) (check 'apt list --upgradable'; phased updates are normal)"
printf '%-17s %s\n' 'reboot required:' "$([ -f /var/run/reboot-required ] && echo YES || echo no)"
echo '-- apt sources:'; ls "$SL"
echo '-- installed packages with no repo (review manually):'
LOCALPKGS=$(apt list '?narrow(?installed, ?obsolete)' 2>/dev/null | grep -v Listing)
printf '%s\n' "${LOCALPKGS:-   none}"
printf '%s\n' "-- log: $LOG"
finish
exit $?
