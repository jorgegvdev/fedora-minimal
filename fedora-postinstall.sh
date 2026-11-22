#!/usr/bin/env bash
# =====================================================================
#  Post-instalación Fedora — mínima y no intrusiva
#  Solo lo necesario para un sistema fácil y estable. No toca el
#  escritorio, extensiones, temas ni ajustes de usuario.
#  Funciona con cualquier escritorio (KDE, GNOME, XFCE...).
#
#  Ejecutar como usuario normal (NO con sudo):  bash fedora-postinstall.sh
#  Pedirá tu contraseña de sudo una vez. Es seguro volver a ejecutarlo.
# =====================================================================
set -uo pipefail

# ---------- Interruptores: "yes" / "no" ----------
DO_SNAPSHOTS="yes"   # Snapper (solo si / es Btrfs): volver atrás si una actualización rompe algo
DO_FIRMWARE="yes"    # Actualizaciones de firmware/BIOS vía fwupd (LVFS)

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
step "8. Mantenimiento"
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
if [[ $HAS_INTEL == yes || $HAS_AMD == yes ]]; then
  echo "Tras reiniciar, verifica aceleración de video con:  vainfo"
fi
