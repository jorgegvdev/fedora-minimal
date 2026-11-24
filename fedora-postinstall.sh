#!/usr/bin/env bash
# =====================================================================
#  Post-instalación Fedora — base estable + herramientas de uso diario
#  Base (DNF, RPM Fusion, Flathub, códecs, snapshots, firmware) y bloques
#  opcionales (CLI, desarrollo, juegos, navegadores, apps). No toca el
#  escritorio, extensiones ni temas.
#  Funciona con cualquier escritorio (KDE, GNOME, XFCE...).
#
#  Ejecutar como usuario normal (NO con sudo):  bash fedora-postinstall.sh
#  Pedirá tu contraseña de sudo una vez. Es seguro volver a ejecutarlo.
# =====================================================================
set -uo pipefail

# ---------- Interruptores: "yes" / "no" ----------
DO_SNAPSHOTS="yes"   # Snapper (solo si / es Btrfs): volver atrás si una actualización rompe algo
DO_FIRMWARE="yes"    # Actualizaciones de firmware/BIOS vía fwupd (LVFS)
DO_CLI="yes"         # Utilidades de terminal, ghostty y starship
DO_DEV="yes"         # git, herramientas de compilación, nvm + Node LTS, clave SSH y GitHub
DO_GAMING="yes"      # Steam, GameMode y MangoHud (nativos)
DO_BROWSERS="yes"    # Firefox, Chrome, Brave y Vivaldi (repos oficiales)
DO_APPS="yes"        # LibreOffice (dnf) + IDEs y apps de usuario (Flatpak)
DO_FONTS="yes"       # Fuentes (Nerd Fonts, Outfit) y paquete de iconos Papirus

NVM_VERSION="v0.41.0"   # https://github.com/nvm-sh/nvm/releases
NERD_FONTS_VERSION="v3.5.1"   # https://github.com/ryanoasis/nerd-fonts/releases

# ---------- Logs: carpeta logs/ junto al script, un par de archivos por ejecución ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR" || { echo "No pude crear $LOG_DIR"; exit 1; }
STAMP="$(date +%F_%H-%M-%S)"
LOG="$LOG_DIR/postinstall-$STAMP.log"        # todo lo que ocurre
ERRLOG="$LOG_DIR/errores-$STAMP.log"         # solo comandos que fallan y avisos
: > "$ERRLOG"
# Todo (stdout y stderr) -> pantalla + log completo.
# DNF escribe su salida normal por stderr, así que el log de errores NO se
# alimenta de stderr: lo llenan run() y warn() (solo fallos reales).
exec > >(tee -a "$LOG") 2>&1

CURRENT_STEP="inicio"
step() { CURRENT_STEP="$*"; echo -e "\n\e[1;34m==> $*\e[0m"; }
warn() {
  echo -e "\e[1;33m[!] $*\e[0m"
  echo "[$(date +%T)] [$CURRENT_STEP] AVISO: $*" >> "$ERRLOG"
}
# Ejecuta un comando; si falla, lo anota en el log de errores con su código de salida.
run() {
  "$@"; local rc=$?
  if (( rc != 0 )); then
    echo -e "\e[1;31m[x] falló (código $rc): $*\e[0m"
    echo "[$(date +%T)] [$CURRENT_STEP] código $rc: $*" >> "$ERRLOG"
  fi
  return $rc
}
info() { echo -e "\e[1;36m[i] $*\e[0m"; }
DNF="run sudo dnf install -y --skip-unavailable"

if [[ $EUID -eq 0 ]]; then
  echo "No lo ejecutes con sudo; ejecútalo como tu usuario."; exit 1
fi
sudo -v || exit 1
# Mantener sudo vivo mientras dura el script
while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done &
KEEPALIVE_PID=$!
trap 'kill "$KEEPALIVE_PID" 2>/dev/null' EXIT

# ---------------------------------------------------------------------
#  Detección (solo hardware y sistema, nunca el escritorio)
# ---------------------------------------------------------------------
FEDORA_VER="$(rpm -E %fedora)"
ROOT_FS="$(findmnt -no FSTYPE / 2>/dev/null || echo unknown)"

# Vendor IDs PCI (fiables): Intel 8086, AMD 1002, NVIDIA 10de
GPU_IDS=""
command -v lspci &>/dev/null || $DNF pciutils
command -v lspci &>/dev/null && GPU_IDS="$(lspci -nn -d ::0300 2>/dev/null; lspci -nn -d ::0302 2>/dev/null; lspci -nn -d ::0380 2>/dev/null)"
HAS_INTEL=no; HAS_AMD=no
grep -qi '\[8086:' <<<"$GPU_IDS" && HAS_INTEL=yes
grep -qi '\[1002:' <<<"$GPU_IDS" && HAS_AMD=yes

step "Entorno detectado"
echo "  Fedora: $FEDORA_VER | Raíz: $ROOT_FS | GPU: Intel=$HAS_INTEL AMD=$HAS_AMD"

# ---------------------------------------------------------------------
step "1. Acelerar DNF (descargas en paralelo)"
if ! grep -q '^max_parallel_downloads' /etc/dnf/dnf.conf; then
  echo 'max_parallel_downloads=10' | sudo tee -a /etc/dnf/dnf.conf >/dev/null
fi

# ---------------------------------------------------------------------
step "2. Actualizar el sistema"
run sudo dnf -y upgrade --refresh

# ---------------------------------------------------------------------
step "3. Repositorios RPM Fusion (free + nonfree)"
$DNF \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"
run sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1 \
  || run sudo dnf config-manager --set-enabled fedora-cisco-openh264 \
  || warn "No se pudo habilitar fedora-cisco-openh264."

# ---------------------------------------------------------------------
step "4. Flathub completo"
run sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
run sudo flatpak remote-modify --no-filter --enable flathub
# Desactivar el remoto "fedora" de flatpak: evita instalar versiones reempaquetadas
# por Fedora; así todo flatpak viene de Flathub (una sola fuente).
if ! flatpak list --system --columns=origin | grep -qx fedora; then
  sudo flatpak remote-modify --disable fedora 2>/dev/null || true
fi

# ---------------------------------------------------------------------
step "5. Códecs multimedia + aceleración de video por hardware"
run sudo dnf -y swap ffmpeg-free ffmpeg --allowerasing
run sudo dnf -y update @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin
$DNF mozilla-openh264 gstreamer1-plugin-openh264 libva-utils

if [[ $HAS_INTEL == yes ]]; then
  $DNF intel-media-driver
fi
if [[ $HAS_AMD == yes ]]; then
  run sudo dnf -y swap mesa-va-drivers mesa-va-drivers-freeworld --allowerasing || true
  run sudo dnf -y swap mesa-vdpau-drivers mesa-vdpau-drivers-freeworld --allowerasing || true
fi

# ---------------------------------------------------------------------
if [[ $DO_SNAPSHOTS == yes ]]; then
  if [[ $ROOT_FS == btrfs ]]; then
    step "6. Snapshots Btrfs"
    $DNF snapper btrfs-assistant
    if ! sudo snapper list-configs 2>/dev/null | grep -q '^root'; then
      run sudo snapper -c root create-config /
      # Límites conservadores para no llenar el disco
      run sudo snapper -c root set-config \
        TIMELINE_CREATE=yes TIMELINE_LIMIT_HOURLY=0 TIMELINE_LIMIT_DAILY=5 \
        TIMELINE_LIMIT_WEEKLY=2 TIMELINE_LIMIT_MONTHLY=1 TIMELINE_LIMIT_YEARLY=0 \
        NUMBER_LIMIT=10 NUMBER_LIMIT_IMPORTANT=5
    fi
    run sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer
    run sudo snapper -c root create -d "Post-instalación limpia" -c important || true
  else
    step "6. Snapshots"
    warn "/ es '$ROOT_FS', no Btrfs: omito snapper."
  fi
fi

# ---------------------------------------------------------------------
if [[ $DO_FIRMWARE == yes ]]; then
  step "7. Firmware (BIOS, EC, etc. vía LVFS)"
  sudo fwupdmgr refresh --force || true
  sudo fwupdmgr get-updates || true
  sudo fwupdmgr update -y --no-reboot-check
  rc=$?
  # 0 = actualizado, 2 = nada que actualizar (ambos normales)
  (( rc == 0 || rc == 2 )) || warn "fwupdmgr update terminó con código $rc."
fi

# ---------------------------------------------------------------------
if [[ $DO_CLI == yes ]]; then
  step "8. Utilidades CLI"
  $DNF btop htop fastfetch ncdu ripgrep fd-find fzf bat eza zoxide \
    jq curl wget unzip 7zip rsync tree
  # ghostty y starship no están en los repos de Fedora: COPR
  if ! command -v ghostty &>/dev/null; then
    run sudo dnf copr enable -y scottames/ghostty && $DNF ghostty
  fi
  if ! command -v starship &>/dev/null; then
    run sudo dnf copr enable -y atim/starship && $DNF starship
  fi
  if command -v starship &>/dev/null && ! grep -q 'starship init bash' ~/.bashrc 2>/dev/null; then
    echo 'eval "$(starship init bash)"' >> ~/.bashrc
  fi
fi

# ---------------------------------------------------------------------
if [[ $DO_DEV == yes ]]; then
  step "9. Desarrollo"
  $DNF git gh
  run sudo dnf group install -y development-tools

  # Identidad de git: solo se pregunta si falta
  if [[ -t 0 ]]; then
    if [[ -z "$(git config --global user.name)" ]]; then
      read -rp "Nombre para git: " GIT_NAME </dev/tty
      [[ -n $GIT_NAME ]] && git config --global user.name "$GIT_NAME"
    fi
    if [[ -z "$(git config --global user.email)" ]]; then
      read -rp "Email para git: " GIT_EMAIL </dev/tty
      [[ -n $GIT_EMAIL ]] && git config --global user.email "$GIT_EMAIL"
    fi
  else
    warn "Sin terminal interactiva: omito la identidad de git."
  fi
  git config --global init.defaultBranch main

  # nvm + Node LTS (nvm.sh no es compatible con 'set -u')
  export NVM_DIR="$HOME/.nvm"
  if [[ ! -s $NVM_DIR/nvm.sh ]]; then
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash \
      || warn "No se pudo instalar nvm."
  fi
  if [[ -s $NVM_DIR/nvm.sh ]]; then
    set +u +o pipefail
    # shellcheck disable=SC1091
    . "$NVM_DIR/nvm.sh"
    run nvm install --lts
    run nvm alias default 'lts/*'
    run npm install -g pnpm @anthropic-ai/claude-code
    set -u -o pipefail
  fi

  # Clave SSH y alta en GitHub
  SSH_KEY="$HOME/.ssh/id_ed25519"
  if [[ ! -f $SSH_KEY ]]; then
    if [[ -t 0 ]]; then
      mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
      run ssh-keygen -t ed25519 -C "$(git config --global user.email)" -f "$SSH_KEY" </dev/tty
    else
      warn "Sin terminal interactiva: omito la clave SSH."
    fi
  fi
  if [[ -f $SSH_KEY.pub && -t 0 ]]; then
    gh auth status &>/dev/null \
      || run gh auth login --hostname github.com --git-protocol ssh --web -s admin:public_key </dev/tty
    if gh auth status &>/dev/null; then
      if ! gh api user/keys --jq '.[].key' | grep -qF "$(awk '{print $2}' "$SSH_KEY.pub")"; then
        run gh ssh-key add "$SSH_KEY.pub" --title "${HOSTNAME}-$(date +%F)"
      fi
    fi
  fi
fi

# ---------------------------------------------------------------------
if [[ $DO_GAMING == yes ]]; then
  step "10. Juegos (Steam, GameMode, MangoHud)"
  $DNF steam gamemode mangohud
  run sudo usermod -aG gamemode "$USER"
fi

# ---------------------------------------------------------------------
if [[ $DO_BROWSERS == yes ]]; then
  step "11. Navegadores"
  $DNF firefox

  # Google Chrome (en Workstation el repo puede existir ya, deshabilitado)
  if [[ ! -f /etc/yum.repos.d/google-chrome.repo ]]; then
    printf '%s\n' '[google-chrome]' 'name=google-chrome' \
      'baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64' \
      'enabled=1' 'gpgcheck=1' 'gpgkey=https://dl.google.com/linux/linux_signing_key.pub' \
      | sudo tee /etc/yum.repos.d/google-chrome.repo >/dev/null
  fi
  run sudo dnf config-manager setopt google-chrome.enabled=1
  $DNF google-chrome-stable

  # Brave
  [[ -f /etc/yum.repos.d/brave-browser.repo ]] \
    || run sudo dnf config-manager addrepo --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
  $DNF brave-browser

  # Vivaldi
  [[ -f /etc/yum.repos.d/vivaldi-fedora.repo ]] \
    || run sudo dnf config-manager addrepo --from-repofile=https://repo.vivaldi.com/archive/vivaldi-fedora.repo
  $DNF vivaldi-stable
fi

# ---------------------------------------------------------------------
if [[ $DO_APPS == yes ]]; then
  step "12. Apps de usuario"
  $DNF libreoffice-writer libreoffice-calc libreoffice-impress
  run sudo flatpak install -y --noninteractive flathub \
    app.zen_browser.zen \
    dev.zed.Zed com.vscodium.codium \
    com.jetbrains.PhpStorm com.jetbrains.DataGrip com.jetbrains.WebStorm \
    com.jetbrains.IntelliJ-IDEA-Ultimate \
    com.spotify.Client com.discordapp.Discord org.videolan.VLC \
    com.bitwarden.desktop md.obsidian.Obsidian com.usebruno.Bruno \
    com.github.tchx84.Flatseal
fi

# ---------------------------------------------------------------------
if [[ $DO_FONTS == yes ]]; then
  step "13. Fuentes e iconos"
  FONT_DIR="$HOME/.local/share/fonts"
  mkdir -p "$FONT_DIR/NerdFonts" "$FONT_DIR/Outfit"
  for font in CascadiaCode CascadiaMono JetBrainsMono FiraCode; do
    if [[ -z "$(ls -A "$FONT_DIR/NerdFonts/$font" 2>/dev/null)" ]]; then
      mkdir -p "$FONT_DIR/NerdFonts/$font"
      curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_VERSION}/${font}.tar.xz" \
        | tar -xJ -C "$FONT_DIR/NerdFonts/$font" \
        || { warn "No se pudo instalar la fuente $font."; rm -rf "$FONT_DIR/NerdFonts/$font"; }
    fi
  done
  if [[ ! -f "$FONT_DIR/Outfit/Outfit[wght].ttf" ]]; then
    curl -fsSL -o "$FONT_DIR/Outfit/Outfit[wght].ttf" \
      "https://github.com/google/fonts/raw/main/ofl/outfit/Outfit%5Bwght%5D.ttf" \
      || warn "No se pudo instalar la fuente Outfit."
  fi
  run fc-cache -f
  # Solo se instala; elegir el tema de iconos es ajuste del escritorio
  $DNF papirus-icon-theme
fi

# ---------------------------------------------------------------------
step "14. Mantenimiento"
run sudo systemctl enable --now fstrim.timer

sleep 1   # dar tiempo a que tee vacíe los buffers
echo -e "\n\e[1;32m✔ Listo.\e[0m"
echo "  Log completo: $LOG"
if [[ -s $ERRLOG ]]; then
  echo -e "  \e[1;33mFallos/avisos: $ERRLOG ($(wc -l < "$ERRLOG") líneas) — revísalo\e[0m"
else
  echo "  Sin fallos registrados."
  rm -f "$ERRLOG"
fi
echo "Reinicia el equipo para aplicar todo:  sudo reboot"
echo "(el reinicio también activa el grupo gamemode, starship y nvm en terminales nuevas)"
if [[ $HAS_INTEL == yes || $HAS_AMD == yes ]]; then
  echo "Tras reiniciar, verifica aceleración de video con:  vainfo"
fi
