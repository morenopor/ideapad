#!/usr/bin/env bash
# upkeep.sh — update and clean the Lenovo Ideapad (Ubuntu 26.04 LTS).
# Safe to re-run: each step is idempotent and skips itself when there is nothing to do.
#
# Usage:
#   bash scripts/upkeep.sh 2>&1 | tee ~/upkeep-$(date +%F).log
#
# Optional: drop the Antigravity tarballs in ~/Downloads before running
#   - Antigravity.tar.gz      (Antigravity 2.x agent app)  -> /opt/antigravity      (cmd: antigravity-app)
#   - Antigravity IDE.tar.gz  (Antigravity IDE 2.x)        -> /opt/antigravity-ide  (cmd: antigravity-ide)
# Always pick the linux x64 build (this laptop is amd64). A tarball is only reinstalled if it changed.
set -u
SL=/etc/apt/sources.list.d
say(){ echo -e "\n=== $* ==="; }
sudo -v || exit 1

say "APT sources"
# Ubuntu disables third-party repos on release upgrades: re-enable known ones.
for name in claude-desktop chatgpt; do
  if [ -f "$SL/$name.list.disabled" ]; then
    sudo mv "$SL/$name.list.disabled" "$SL/$name.list"
    sudo sed -i 's/^#\s*deb /deb /' "$SL/$name.list"
    echo "re-enabled $name"
  fi
done
# Leftover PPA for an older release (e.g. jammy) — drop it unless the NVIDIA driver comes from it.
for f in "$SL"/graphics-drivers-ubuntu-ppa-*.sources; do
  [ -e "$f" ] || continue
  case "$f" in *"$(lsb_release -cs)"*) continue;; esac
  if apt-cache policy 'nvidia-driver-*' 2>/dev/null | grep -q launchpad; then
    echo "KEEP $f (NVIDIA driver installed from PPA)"
  else sudo rm "$f"; echo "removed $f"; fi
done
# Convert any remaining one-line .list files to deb822 .sources.
ls "$SL"/*.list >/dev/null 2>&1 && sudo apt -y modernize-sources
# A .sources file with the same repo twice triggers "configured multiple times": keep the first stanza.
for f in "$SL"/*.sources; do
  n=$(grep -c '^URIs:' "$f")
  if [ "$n" -gt 1 ] && [ "$(grep '^URIs:' "$f" | sort -u | wc -l)" -eq 1 ]; then
    sudo cp "$f" "$f.dup.bak"
    awk 'BEGIN{RS="";ORS="\n"} NR==1' "$f.dup.bak" | sudo tee "$f" >/dev/null
    echo "deduplicated $f"
  fi
done

say "System update"
sudo apt update
sudo DEBIAN_FRONTEND=noninteractive apt -y full-upgrade
sudo snap refresh
command -v npm >/dev/null && sudo npm update -g
# AI CLIs installed as global npm packages (kept current by the npm update above).
command -v gemini >/dev/null || sudo npm install -g @google/gemini-cli
command -v codex >/dev/null || sudo npm install -g @openai/codex
# Backups left by modernize-sources / de-duplication are no longer needed once apt update has succeeded.
sudo rm -f "$SL"/*.list.bak "$SL"/*.dup.bak

say "Cleanup"
# Old kernels left from previous releases (no longer in any repo); never touches the running one.
OLDK=$(apt list '?narrow(?installed, ?obsolete, ?name(^linux-))' 2>/dev/null | cut -d/ -f1 | grep -v Listing | grep -v -- "$(uname -r)")
[ -n "$OLDK" ] && sudo apt -y purge $OLDK
# Obsolete libraries / transitional packages: mark as auto so autoremove drops them only if nothing needs them.
OLDLIB=$(apt list '?narrow(?installed, ?obsolete, ?or(?name(^lib), ?name(^policykit-1$)))' 2>/dev/null | cut -d/ -f1 | grep -v Listing)
[ -n "$OLDLIB" ] && sudo apt-mark auto $OLDLIB >/dev/null
sudo apt -y autoremove --purge
sudo apt -y autoclean

say "Preferred apps (same toolset as the iMac)"
# CLI toolset. Ubuntu dropped exa/neofetch/tldr: eza, fastfetch and tealdeer replace them.
APPS="micro eza ncdu tree btop htop fastfetch nmap whois netcat-openbsd lynx tealdeer jq git curl wget rsync"
MISSING=$(for p in $APPS; do dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q "ok installed" || echo "$p"; done)
# Remove the obsolete predecessors first (tealdeer conflicts with the old tldr packages).
OLDTOOLS=$(dpkg-query -W -f='${Package}\n' neofetch tldr tldr-hs exa 2>/dev/null)
[ -n "$OLDTOOLS" ] && sudo apt -y purge $OLDTOOLS
if [ -n "$MISSING" ]; then sudo apt -y install $MISSING; else echo "all CLI tools present"; fi
command -v tldr >/dev/null && tldr --update >/dev/null 2>&1
# VS Code: preferred as the classic snap (the old .deb has no repo and stopped updating).
if dpkg-query -W -f='${Status}' code 2>/dev/null | grep -q "ok installed"; then sudo apt -y purge code; fi
snap list code >/dev/null 2>&1 || sudo snap install --classic code
# micro is the default editor (terminal, sudoedit, git).
sudo update-alternatives --set editor /usr/bin/micro >/dev/null 2>&1
git config --global core.editor micro
# Apps no longer used on this laptop: remove them and their repos.
UNWANTED=$(dpkg-query -W -f='${Package}\n' teamviewer terraform 2>/dev/null)
[ -n "$UNWANTED" ] && sudo apt -y purge $UNWANTED && sudo apt -y autoremove --purge
sudo rm -f "$SL"/hashicorp.* "$SL"/teamviewer*
BRC=~/.bashrc; MARK="# >>> ideapad preferences >>>"
if ! grep -qF "$MARK" "$BRC"; then
  cat >> "$BRC" <<'RC'
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
[ -n "$LANMISSING" ] && sudo apt -y install $LANMISSING
systemctl is-active --quiet avahi-daemon || sudo systemctl enable --now avahi-daemon
# LocalSend: user-level Flatpak from Flathub (never system-wide).
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak info --user org.localsend.localsend_app >/dev/null 2>&1 || flatpak install --user -y flathub org.localsend.localsend_app
flatpak update --user -y --noninteractive
# GSConnect: user-scoped GNOME Shell extension (talks to KDE Connect on the iPhone). Do NOT install the kdeconnect desktop package.
GSC=gsconnect@andyholmes.github.io
if ! gnome-extensions info "$GSC" >/dev/null 2>&1; then
  echo "GSConnect missing: GNOME Shell will ask you to confirm the install from extensions.gnome.org"
  gdbus call --session --dest org.gnome.Shell.Extensions --object-path /org/gnome/Shell/Extensions \
    --method org.gnome.Shell.Extensions.InstallRemoteExtension "$GSC" >/dev/null 2>&1 \
    || echo "could not reach GNOME Shell (run this from a desktop session)"
fi
dpkg-query -W -f='${Status}' kdeconnect 2>/dev/null | grep -q "ok installed" && echo "WARNING: kdeconnect package is installed and conflicts with GSConnect"
# ChatGPT desktop: official amd64 .deb (it adds chatgpt.sources, so routine updates come via apt). Reinstalls from ~/Downloads if missing or older.
CGDEB=$(find ~/Downloads -maxdepth 1 -iname 'chatgpt*_amd64.deb' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
CGPKG=$(dpkg -S /usr/bin/chatgpt 2>/dev/null | cut -d: -f1)
if [ -n "$CGDEB" ]; then
  NEWV=$(dpkg-deb -f "$CGDEB" Version); CURV=$([ -n "$CGPKG" ] && dpkg-query -W -f='${Version}' "$CGPKG")
  if [ -z "$CURV" ] || dpkg --compare-versions "$NEWV" gt "$CURV"; then sudo apt -y install "$CGDEB"; fi
elif [ -z "$CGPKG" ]; then echo "ChatGPT desktop missing: download the official amd64 .deb to ~/Downloads and re-run"; fi
# Custom AirPlay launcher ("iPhone AirPlay" -> receiver "Gabe Lenovo"). Created only if missing; existing files are kept as-is.
mkdir -p ~/.local/bin ~/.local/share/applications
if [ ! -e ~/.local/bin/gabe-iphone-airplay ]; then
  cat > ~/.local/bin/gabe-iphone-airplay <<'AIR'
#!/usr/bin/env bash
# AirPlay receiver for the iPhone: PIN pairing, software video decoding, fixed TCP/UDP ports 35000-35002.
exec uxplay -n 'Gabe Lenovo' -p 35000 -pin -avdec "$@"
AIR
  chmod +x ~/.local/bin/gabe-iphone-airplay; echo "created ~/.local/bin/gabe-iphone-airplay"
fi
if [ ! -e ~/.local/share/applications/gabe-iphone-airplay.desktop ]; then
  cat > ~/.local/share/applications/gabe-iphone-airplay.desktop <<DESK
[Desktop Entry]
Name=iPhone AirPlay
Comment=Receive AirPlay screen and audio from the iPhone (UxPlay)
Exec=$HOME/.local/bin/gabe-iphone-airplay
Icon=video-display
Terminal=false
Type=Application
Categories=AudioVideo;Network;
DESK
  update-desktop-database ~/.local/share/applications 2>/dev/null; echo "created iPhone AirPlay launcher"
fi

install_tarball(){ # $1=tarball $2=dest $3=command $4=desktop-name
  local tb="$1" dest="$2" cmd="$3" label="$4" sum t s bin icon
  sum=$(sha256sum "$tb" | cut -d' ' -f1)
  if [ "$(cat "$dest/.tarball.sha256" 2>/dev/null)" = "$sum" ]; then echo "$label already up to date"; return; fi
  [ -d ~/.antigravity ] && [ ! -d ~/antigravity-backup-$(date +%F) ] && cp -a ~/.antigravity ~/antigravity-backup-$(date +%F)
  t=$(mktemp -d); tar -xzf "$tb" -C "$t"; s="$t"
  [ "$(ls -A "$t" | wc -l)" -eq 1 ] && [ -d "$t"/* ] && s=$(echo "$t"/*)
  sudo rm -rf "$dest" && sudo mkdir -p "$dest" && sudo cp -a "$s"/. "$dest"/ && rm -rf "$t"
  [ -f "$dest/chrome-sandbox" ] && sudo chown root:root "$dest/chrome-sandbox" && sudo chmod 4755 "$dest/chrome-sandbox"
  bin=$(find "$dest" -maxdepth 2 -type f -executable -iname 'antigravity*' ! -name '*.so*' | head -1)
  icon=$(find "$dest" -iname '*.png' | grep -i -m1 -E 'antigravity|code|icon')
  if [ -z "$bin" ]; then echo "$label: executable not found, contents:"; ls "$dest"; return; fi
  sudo ln -sf "$bin" "/usr/local/bin/$cmd"
  mkdir -p ~/.local/share/applications
  cat > ~/.local/share/applications/$cmd.desktop <<DESK
[Desktop Entry]
Name=$label
Exec=/usr/local/bin/$cmd %F
Icon=${icon:-utilities-terminal}
Type=Application
Categories=Development;IDE;
DESK
  update-desktop-database ~/.local/share/applications 2>/dev/null
  echo "$sum" | sudo tee "$dest/.tarball.sha256" >/dev/null
  echo "$label installed: $bin"
}

say "Antigravity 2.x (tarballs)"
AG=$(find ~/Downloads -maxdepth 1 -iname 'antigravity*.tar.gz' ! -iname '*ide*' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
IDE=$(find ~/Downloads -maxdepth 1 -iname 'antigravity*ide*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
if [ -n "$AG" ]; then install_tarball "$AG" /opt/antigravity antigravity-app "Antigravity"; else echo "no Antigravity.tar.gz in ~/Downloads"; fi
if [ -n "$IDE" ]; then install_tarball "$IDE" /opt/antigravity-ide antigravity-ide "Antigravity IDE"; else echo "no 'Antigravity IDE.tar.gz' in ~/Downloads"; fi
# Antigravity 1.x came from an apt repo that stopped at 1.23.2; once the 2.x IDE is in /opt, drop the old package and its repo.
if [ -x /opt/antigravity-ide/antigravity-ide ] && dpkg-query -W -f='${Status}' antigravity 2>/dev/null | grep -q "ok installed"; then
  sudo apt -y purge antigravity
fi
[ -x /opt/antigravity-ide/antigravity-ide ] && sudo rm -f "$SL"/antigravity.* /etc/apt/keyrings/antigravity-repo-key.gpg
command -v agy >/dev/null || echo "agy CLI missing: curl -fsSL https://antigravity.google/cli/install.sh | bash"

ver(){ # Antigravity product version: IDE -> product.json ideVersion; agent app -> package.json inside app.asar
  local d="$1" v=""
  v=$(grep -oE '"ideVersion": *"[^"]+"' "$d/resources/app/product.json" 2>/dev/null | cut -d'"' -f4)
  [ -z "$v" ] && [ -f "$d/resources/app.asar" ] && v=$(node -e 'const fs=require("fs"),b=fs.readFileSync(process.argv[1]),h=JSON.parse(b.slice(16,16+b.readUInt32LE(12)).toString()),e=h.files["package.json"],o=8+b.readUInt32LE(4)+Number(e.offset);console.log(JSON.parse(b.slice(o,o+e.size)).version)' "$d/resources/app.asar" 2>/dev/null)
  [ -z "$v" ] && v=$(grep -m1 -oE '"version": *"[^"]+"' "$d/resources/app/package.json" 2>/dev/null | cut -d'"' -f4)
  echo "${v:-n/a}"
}
say "SUMMARY"
lsb_release -ds; uname -r
echo "gemini:          $(gemini --version 2>/dev/null)"
echo "agy:             $(agy --version 2>/dev/null | head -1)"
echo "codex:           $(codex --version 2>/dev/null | head -1) [$(readlink -f "$(command -v codex)" 2>/dev/null)]"
echo "antigravity 2.x: $(ver /opt/antigravity)"
echo "antigravity-ide: $(ver /opt/antigravity-ide)"
echo "node: $(node -v 2>/dev/null)  npm: $(npm -v 2>/dev/null)"
echo "vscode (snap):   $(code --version 2>/dev/null | head -1)"
echo "editor:          $(readlink -f /usr/bin/editor)"
echo "localsend:       $(flatpak info --user org.localsend.localsend_app 2>/dev/null | awk -F': *' '/Version/{print $2}')"
echo "gsconnect:       $(gnome-extensions info gsconnect@andyholmes.github.io 2>/dev/null | grep -E 'Version|Enabled|State' | sed 's/^ *//' | paste -sd' ' -)"
echo "uxplay:          $(dpkg-query -W -f='${Version}' uxplay 2>/dev/null)"
echo "avahi-daemon:    $(dpkg-query -W -f='${Version}' avahi-daemon 2>/dev/null) ($(systemctl is-active avahi-daemon 2>/dev/null))"
echo "chatgpt:         $(p=$(dpkg -S /usr/bin/chatgpt 2>/dev/null | cut -d: -f1); [ -n "$p" ] && dpkg-query -W -f='${Version}' "$p")"
echo "ufw:             $(sudo ufw status 2>/dev/null | head -1)"
echo "nvidia: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo n/a)"
echo "pending upgrades: $(apt list --upgradable 2>/dev/null | grep -c upgradable) (phased updates are normal)"
echo "reboot required: $([ -f /var/run/reboot-required ] && echo YES || echo no)"
echo "-- apt sources:"; ls "$SL"
echo "-- installed packages with no repo (review manually; ChatGPT is never listed here):"
CGP=$(dpkg -S /usr/bin/chatgpt 2>/dev/null | cut -d: -f1)
apt list '?narrow(?installed, ?obsolete)' 2>/dev/null | grep -v Listing | grep -v "^${CGP:-__none__}/"
