#!/usr/bin/env bash
# =====================================================================
#  Post-instalación Fedora — base estable + herramientas de uso diario
#  Base (DNF, RPM Fusion, Flathub, códecs, snapshots, firmware) y bloques
#  opcionales (CLI, desarrollo, juegos, navegadores, apps, temas). Instala
#  temas, iconos y cursores pero no activa ninguno ni toca extensiones.
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
DO_DEV="yes"         # git, herramientas de compilación, nvm + Node LTS, gentle-ai, clave SSH y GitHub
DO_GAMING="yes"      # Steam, GameMode y MangoHud (nativos)
DO_BROWSERS="yes"    # Google Chrome (repo oficial) y Helium (COPR oficial imput/helium)
DO_APPS="yes"        # LibreOffice (dnf) + IDEs y apps de usuario (Flatpak)
DO_FONTS="yes"       # Fuentes (Nerd Fonts, Outfit) y paquete de iconos Papirus
DO_THEMES="yes"      # Temas GTK/shell (Gruvbox, Orchis, Graphite), iconos Gruvbox Plus y cursores (Bibata, Mocu)

NVM_VERSION="v0.41.0"   # https://github.com/nvm-sh/nvm/releases
NERD_FONTS_VERSION="v3.5.1"   # https://github.com/ryanoasis/nerd-fonts/releases

# Temas, iconos y cursores: todo fijado a una versión exacta. Los repos van por commit
# (git verifica el hash al descargar); los tarballs de Bibata, por sha256.
BIBATA_VERSION="v2.0.7"   # https://github.com/ful1e5/Bibata_Cursor/releases
BIBATA_CLASSIC_SHA256="7d3495864e5bbef02f5e77de760b2905903b63c71495a78ef6306d19a3b556d8"
BIBATA_ICE_SHA256="a68cae60c4dc706350e194ebc91c5fe48bc7bc9d59e119555834a2a7ee5078ef"
MOCU_COMMIT="efdd71279b79bf1e2566c38becc5e7c4ab2d900c"            # sevmeyer/mocu-xcursor
GRUVBOX_PLUS_COMMIT="d234e270f5b97c791f891f4f21f346c07d67d64f"    # SylEleuth/gruvbox-plus-icon-pack
GRUVBOX_GTK_COMMIT="578cd220b5ff6e86b078a6111d26bb20ec8c733f"     # Fausto-Korpsvart/Gruvbox-GTK-Theme
ORCHIS_COMMIT="a4c48a425e63808345e824495964bd9c2f462e04"          # vinceliuice/Orchis-theme
GRAPHITE_COMMIT="364173f47407164948788e4abb5e2eb46600f71a"        # vinceliuice/Graphite-gtk-theme

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
# Un rpmdb con versiones duplicadas (típico tras una actualización interrumpida)
# hace fallar luego instalaciones multilib como Steam (i686 vs x86_64).
if [[ -n "$(dnf repoquery --duplicates -q 2>/dev/null)" ]]; then
  warn "Hay paquetes RPM duplicados (actualización previa incompleta); limpiando"
  run sudo dnf -y remove --duplicates
fi

# ---------------------------------------------------------------------
step "3. Repositorios RPM Fusion (free + nonfree)"
$DNF \
  "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
  "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"
run sudo dnf config-manager setopt fedora-cisco-openh264.enabled=1

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
# noopenh264 (stub de Fedora) choca con openh264 (Cisco): dejar solo el real
if rpm -q noopenh264 openh264 &>/dev/null; then
  run sudo dnf -y remove noopenh264
fi

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
  # (--skip-unavailable oculta un paquete inexistente: se comprueba después)
  if ! command -v ghostty &>/dev/null; then
    run sudo dnf copr enable -y scottames/ghostty && $DNF ghostty
    command -v ghostty &>/dev/null \
      || warn "ghostty no se instaló: puede que el COPR no tenga build para Fedora $FEDORA_VER."
  fi
  if ! command -v starship &>/dev/null; then
    run sudo dnf copr enable -y atim/starship && $DNF starship
    command -v starship &>/dev/null \
      || warn "starship no se instaló: puede que el COPR no tenga build para Fedora $FEDORA_VER."
  fi

  # Ghostty: Gruvbox (Light en modo claro, Dark en oscuro), 10 % de transparencia + CaskaydiaCove Nerd Font.
  # Solo añade las claves que falten: lo que ya hayas configurado tú se respeta.
  GHOSTTY_DIR="$HOME/.config/ghostty"
  if [[ -f $GHOSTTY_DIR/config ]]; then
    GHOSTTY_CFG="$GHOSTTY_DIR/config"
  else
    GHOSTTY_CFG="$GHOSTTY_DIR/config.ghostty"   # nombre por defecto desde Ghostty 1.2
  fi
  mkdir -p "$GHOSTTY_DIR" && touch "$GHOSTTY_CFG"
  ghostty_set() {
    grep -qE "^[[:space:]]*$1[[:space:]]*=" "$GHOSTTY_CFG" || echo "$1 = $2" >> "$GHOSTTY_CFG"
  }
  ghostty_set theme "light:Gruvbox Light,dark:Gruvbox Dark"
  ghostty_set background-opacity 0.9
  ghostty_set font-family "CaskaydiaCove Nerd Font"
  ghostty_set font-size 12
  ghostty_set window-padding-x 10
  ghostty_set window-padding-y 8
  ghostty_set window-padding-balance true

  # Starship: prompt minimalista de una línea al estilo catppuccin_mocha de oh-my-posh,
  # con los colores del tema activo de Ghostty (Gruvbox por defecto).
  # Usa colores ANSI, así sigue al tema de Ghostty. Necesita una Nerd Font (bloque 13).
  # Si ya tienes tu propio starship.toml no se toca (salvo el preset Pastel Powerline
  # que instalaba una versión anterior del script, que se reemplaza).
  if command -v starship &>/dev/null; then
    STARSHIP_CFG="$HOME/.config/starship.toml"
    if [[ ! -f $STARSHIP_CFG || "$(<"$STARSHIP_CFG")" == "$(starship preset pastel-powerline)" ]]; then
      mkdir -p "$HOME/.config"
      cat > "$STARSHIP_CFG" <<'EOF'
"$schema" = "https://starship.rs/config-schema.json"

# Estilo minimalista inspirado en el tema catppuccin_mocha de oh-my-posh:
# una línea, sin fondos. Usa los colores ANSI de la terminal, así sigue
# automáticamente al tema de Ghostty (Gruvbox Light / Dark).
format = "$os$username$hostname $directory$git_branch$git_state$git_status$python$cmd_duration$character"
add_newline = true

[os]
disabled = false
format = "[$symbol]($style) "
style = "bold"

[os.symbols]
Fedora = "\uf30a"
Linux = "\uf17c"

[username]
show_always = true
format = "[$user]($style)"
style_user = "blue"
style_root = "bold red"

[hostname]
ssh_only = false
format = "[@$hostname]($style)"
style = "blue"

[directory]
format = "[$path]($style)[$read_only]($read_only_style) "
style = "purple"
read_only = " \uf023"
truncation_length = 4
truncate_to_repo = false

[git_branch]
format = "[$symbol$branch]($style) "
symbol = "\ue725"
style = "bold blue"

[git_state]
format = "[$state( $progress_current/$progress_total)]($style) "
style = "yellow"

[git_status]
format = "([$all_status$ahead_behind]($style) )"
style = "yellow"

[python]
format = "[\ue73c $virtualenv]($style) "
style = "green"
detect_extensions = []
detect_files = []

[cmd_duration]
format = "[\uf252 $duration]($style) "
style = "yellow"
min_time = 2000

[character]
success_symbol = "[›](bold)"
error_symbol = "[›](bold red)"
vimcmd_symbol = "[‹](bold green)"
EOF
    else
      info "Ya tienes un starship.toml propio ($STARSHIP_CFG); no lo cambio."
    fi
    # shellcheck disable=SC2016  # debe quedar literal en .bashrc
    grep -q 'starship init bash' ~/.bashrc 2>/dev/null \
      || echo 'eval "$(starship init bash)"' >> ~/.bashrc
  fi

  # Fastfetch: logo grande de Fedora + 16 módulos con iconos Nerd Font (necesita la fuente del bloque 13).
  # Si ya tienes tu propia config, no se toca.
  FASTFETCH_CFG="$HOME/.config/fastfetch/config.jsonc"
  if [[ ! -f $FASTFETCH_CFG ]]; then
    mkdir -p "${FASTFETCH_CFG%/*}"
    cat > "$FASTFETCH_CFG" <<'EOF'
{
  "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
  "logo": {
    "source": "Fedora",
    "padding": { "top": 1, "left": 1, "right": 2 }
  },
  "display": {
    "separator": "  "
  },
  "modules": [
    { "type": "title", "format": "{#1}{user-name-colored}" },
    { "type": "custom", "format": "────────────────────────────" },
    { "type": "os",           "key": "󰍹 OS",        "keyColor": "blue",    "keyWidth": 14 },
    { "type": "host",         "key": "󰌢 Host",      "keyColor": "green",   "keyWidth": 14 },
    { "type": "kernel",       "key": " Kernel",    "keyColor": "yellow",  "keyWidth": 14 },
    { "type": "packages",     "key": "󰏖 Paquetes",  "keyColor": "magenta", "keyWidth": 14 },
    { "type": "de",           "key": "󰕮 DE",        "keyColor": "blue",    "keyWidth": 14 },
    { "type": "wm",           "key": "󱂬 WM",        "keyColor": "magenta", "keyWidth": 14 },
    { "type": "shell",        "key": "󰞷 Shell",     "keyColor": "green",   "keyWidth": 14 },
    { "type": "terminal",     "key": "󰆍 Terminal",  "keyColor": "cyan",    "keyWidth": 14 },
    { "type": "terminalfont", "key": "󰛖 Fuente",    "keyColor": "magenta", "keyWidth": 14 },
    { "type": "uptime",       "key": "󰅐 Uptime",    "keyColor": "cyan",    "keyWidth": 14 },
    { "type": "cpu",          "key": "󰻠 CPU",       "keyColor": "red",     "keyWidth": 14 },
    { "type": "gpu",          "key": "󰢮 GPU",       "keyColor": "yellow",  "keyWidth": 14 },
    { "type": "display",      "key": "󰍺 Pantalla",  "keyColor": "blue",    "keyWidth": 14 },
    { "type": "memory",       "key": "󰍛 RAM",       "keyColor": "cyan",    "keyWidth": 14 },
    { "type": "disk",         "key": "󰋊 Disco",     "keyColor": "white",   "keyWidth": 14, "folders": "/" },
    { "type": "battery",      "key": "󰁹 Batería",   "keyColor": "green",   "keyWidth": 14 },
    { "type": "custom", "format": "────────────────────────────" },
    { "type": "colors", "symbol": "circle" }
  ]
}
EOF
  else
    info "Ya tienes una config de fastfetch ($FASTFETCH_CFG); no la cambio."
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

  # gentle-ai: capa de configuración para agentes de IA (Claude Code, OpenCode...).
  # https://github.com/Gentleman-Programming/gentle-ai
  # Solo instala el binario en ~/.local/bin (con checksum verificado). Configurar los
  # agentes es interactivo: ejecuta `gentle-ai` después del script.
  if ! command -v gentle-ai &>/dev/null && [[ ! -x $HOME/.local/bin/gentle-ai ]]; then
    curl -fsSL https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh \
      | bash -s -- --method binary --dir "$HOME/.local/bin" \
      || warn "No se pudo instalar gentle-ai."
  fi

  # Clave SSH y alta en GitHub
  SSH_KEY="$HOME/.ssh/id_ed25519"
  if [[ ! -f $SSH_KEY ]]; then
    if [[ -t 0 ]]; then
      mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
      SSH_COMMENT="$(git config --global user.email)"
      [[ -n $SSH_COMMENT ]] || SSH_COMMENT="$USER@$HOSTNAME"
      run ssh-keygen -t ed25519 -C "$SSH_COMMENT" -f "$SSH_KEY" </dev/tty
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
  step "11. Navegadores (Google Chrome + Helium, predeterminado)"

  # Limpieza de navegadores que instalaban versiones anteriores del script.
  # Firefox se deja (viene de serie). Los datos de usuario (~/.config, ~/.var/app) se conservan.
  for pkg in brave-browser vivaldi-stable; do
    if rpm -q "$pkg" &>/dev/null; then
      info "Quitando $pkg"
      run sudo dnf -y remove "$pkg"
    fi
  done
  for repo in brave-browser.repo vivaldi-fedora.repo vivaldi.repo; do
    if [[ -f /etc/yum.repos.d/$repo ]]; then
      run sudo rm -f "/etc/yum.repos.d/$repo"
    fi
  done
  if flatpak list --system --app --columns=application 2>/dev/null | grep -qx app.zen_browser.zen; then
    info "Quitando Zen Browser (Flatpak)"
    run sudo flatpak uninstall -y --noninteractive --system app.zen_browser.zen
  fi
  if flatpak list --user --app --columns=application 2>/dev/null | grep -qx app.zen_browser.zen; then
    run flatpak uninstall -y --noninteractive --user app.zen_browser.zen
  fi

  # Google Chrome (en Workstation el repo puede existir ya, deshabilitado)
  if [[ ! -f /etc/yum.repos.d/google-chrome.repo ]]; then
    printf '%s\n' '[google-chrome]' 'name=google-chrome' \
      'baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64' \
      'enabled=1' 'gpgcheck=1' 'gpgkey=https://dl.google.com/linux/linux_signing_key.pub' \
      | sudo tee /etc/yum.repos.d/google-chrome.repo >/dev/null
  fi
  run sudo dnf config-manager setopt google-chrome.enabled=1
  # Importar la clave antes (el %post de Chrome puede fallar por el bloqueo del keyring)
  run sudo rpm --import https://dl.google.com/linux/linux_signing_key.pub
  $DNF google-chrome-stable
  # Si Chrome ya está como RPM, quitar el Flatpak para que no salga duplicado en el menú.
  # Sin --delete-data: los datos de ~/.var/app/com.google.Chrome se conservan.
  if rpm -q google-chrome-stable &>/dev/null \
     && flatpak list --app --columns=application 2>/dev/null | grep -qx com.google.Chrome; then
    info "Chrome está como RPM y como Flatpak: quitando el Flatpak"
    run flatpak uninstall -y --noninteractive com.google.Chrome
  fi

  # Helium (Chromium sin Google, de imput.net). COPR mantenido por el propio proyecto.
  if ! rpm -q helium-bin &>/dev/null; then
    run sudo dnf copr enable -y imput/helium && $DNF helium-bin
  fi

  # Helium como navegador predeterminado (xdg-mime vale para cualquier escritorio;
  # xdg-settings además avisa a GNOME/KDE si hay sesión gráfica)
  if [[ -f /usr/share/applications/helium.desktop ]]; then
    command -v xdg-mime &>/dev/null || $DNF xdg-utils
    run xdg-mime default helium.desktop \
      x-scheme-handler/http x-scheme-handler/https text/html application/xhtml+xml
    xdg-settings set default-web-browser helium.desktop 2>/dev/null || true
    info "Helium es el navegador predeterminado"
  else
    warn "Helium no está instalado: no se cambia el navegador predeterminado."
  fi
fi

# ---------------------------------------------------------------------
if [[ $DO_APPS == yes ]]; then
  step "12. Apps de usuario"
  $DNF libreoffice-writer libreoffice-calc libreoffice-impress
  run sudo flatpak install -y --noninteractive flathub \
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
if [[ $DO_THEMES == yes ]]; then
  step "14. Temas, iconos y cursores"
  # Solo se instalan en tu home; elegir cuál usar es ajuste del escritorio
  # (GNOME Retoques: Apariencia; el tema del shell requiere la extensión User Themes).
  # sassc compila los temas; xcursorgen, rsvg-convert y xmlstarlet compilan Mocu.
  $DNF git sassc xcursorgen librsvg2-tools xmlstarlet

  ICON_DIR="$HOME/.local/share/icons"
  THEME_DIR="$HOME/.themes"
  mkdir -p "$ICON_DIR" "$THEME_DIR"
  WORK="$(mktemp -d)"

  # Descarga un commit exacto de un repo (git verifica el hash). Con rutas extra,
  # baja solo esas carpetas (sparse-checkout) para no traer cientos de MB inútiles.
  # Uso: git_pinned URL COMMIT DESTINO [carpeta...]
  git_pinned() {
    local url=$1 sha=$2 dir=$3; shift 3
    rm -rf "$dir"; mkdir -p "$dir" || return 1
    git -C "$dir" init -q \
      && git -C "$dir" remote add origin "$url" \
      && { (( $# == 0 )) || git -C "$dir" sparse-checkout set "$@"; } \
      && git -C "$dir" fetch -q --depth 1 --filter=blob:none origin "$sha" \
      && git -C "$dir" checkout -q FETCH_HEAD
  }

  # Cursores Bibata (tarball de la release, sha256 verificado)
  for variant in Classic Ice; do
    [[ -d $ICON_DIR/Bibata-Modern-$variant ]] && continue
    case $variant in
      Classic) expected=$BIBATA_CLASSIC_SHA256 ;;
      Ice)     expected=$BIBATA_ICE_SHA256 ;;
    esac
    tarball="$WORK/Bibata-Modern-$variant.tar.xz"
    if curl -fsSL -o "$tarball" \
         "https://github.com/ful1e5/Bibata_Cursor/releases/download/${BIBATA_VERSION}/Bibata-Modern-$variant.tar.xz" \
       && echo "$expected  $tarball" | sha256sum -c --quiet -; then
      run tar -xJf "$tarball" -C "$ICON_DIR"
    else
      warn "No se pudo instalar el cursor Bibata-Modern-$variant (descarga o checksum)."
    fi
  done

  # Cursores Mocu (se compilan con make.sh; "Right" = mano derecha)
  if [[ ! -d $ICON_DIR/Mocu-Black-Right || ! -d $ICON_DIR/Mocu-White-Right ]]; then
    if git_pinned https://github.com/sevmeyer/mocu-xcursor.git "$MOCU_COMMIT" "$WORK/mocu" \
       && (cd "$WORK/mocu" && ./make.sh >/dev/null); then
      run cp -a "$WORK/mocu/dist/Mocu-Black-Right" "$WORK/mocu/dist/Mocu-White-Right" "$ICON_DIR/"
    else
      warn "No se pudo instalar el cursor Mocu."
    fi
  fi

  # Iconos Gruvbox Plus (Papirus ya viene del bloque 13)
  if [[ ! -d $ICON_DIR/Gruvbox-Plus-Dark ]]; then
    if git_pinned https://github.com/SylEleuth/gruvbox-plus-icon-pack.git "$GRUVBOX_PLUS_COMMIT" \
         "$WORK/gruvbox-plus" Gruvbox-Plus-Dark; then
      run cp -a "$WORK/gruvbox-plus/Gruvbox-Plus-Dark" "$ICON_DIR/"
      run gtk-update-icon-cache -q -f "$ICON_DIR/Gruvbox-Plus-Dark"
    else
      warn "No se pudo instalar los iconos Gruvbox Plus."
    fi
  fi

  # Temas GTK + shell (variante oscura)
  if [[ ! -d $THEME_DIR/Gruvbox-Dark ]]; then
    if git_pinned https://github.com/Fausto-Korpsvart/Gruvbox-GTK-Theme.git "$GRUVBOX_GTK_COMMIT" \
         "$WORK/gruvbox-gtk" themes; then
      run bash -c 'cd "$1/themes" && ./install.sh -d "$2" -c dark' _ "$WORK/gruvbox-gtk" "$THEME_DIR"
    else
      warn "No se pudo instalar el tema Gruvbox GTK."
    fi
  fi
  if [[ ! -d $THEME_DIR/Orchis-Dark ]]; then
    if git_pinned https://github.com/vinceliuice/Orchis-theme.git "$ORCHIS_COMMIT" "$WORK/orchis"; then
      run bash -c 'cd "$1" && ./install.sh -d "$2" -c dark -s standard' _ "$WORK/orchis" "$THEME_DIR"
    else
      warn "No se pudo instalar el tema Orchis."
    fi
  fi
  if [[ ! -d $THEME_DIR/Graphite-Dark ]]; then
    if git_pinned https://github.com/vinceliuice/Graphite-gtk-theme.git "$GRAPHITE_COMMIT" "$WORK/graphite"; then
      run bash -c 'cd "$1" && ./install.sh -d "$2" -c dark -s standard' _ "$WORK/graphite" "$THEME_DIR"
      # Su instalador deja además una app suelta (gnome-theme-switcher) que no se pidió
      rm -f "$HOME/.local/bin/gnome-theme-switcher" \
            "$HOME/.local/share/applications/org.gnome.GTK4ThemeSwitcher.desktop"
    else
      warn "No se pudo instalar el tema Graphite."
    fi
  fi

  rm -rf "$WORK"
fi

# ---------------------------------------------------------------------
step "15. Mantenimiento"
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
if [[ -x $HOME/.local/bin/gentle-ai ]] || command -v gentle-ai &>/dev/null; then
  echo "Configura tus agentes de IA (interactivo):  gentle-ai"
fi
if [[ $HAS_INTEL == yes || $HAS_AMD == yes ]]; then
  echo "Tras reiniciar, verifica aceleración de video con:  vainfo"
fi
