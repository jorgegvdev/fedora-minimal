# fedora-minimal

Post-instalación para Fedora Workstation: base estable (DNF, RPM Fusion, Flathub, códecs, snapshots, firmware) más herramientas de uso diario (CLI, desarrollo, juegos, navegadores, apps). Cada bloque se apaga con un interruptor. Pensado para GNOME: aplica iconos, cursor y fuentes con `gsettings`; instala y activa las extensiones.

Sirve en cualquier equipo, porque detecta el hardware en vez de asumirlo.

## Uso

En una instalación limpia de Fedora (no necesita `git`):

```bash
curl -fsSL https://raw.githubusercontent.com/jorgegvdev/fedora-minimal/main/fedora-postinstall.sh -o fedora-postinstall.sh
bash fedora-postinstall.sh
```

- Ejecútalo como usuario normal, **no** con `sudo`. Pide tu contraseña una vez.
- Es seguro volver a ejecutarlo.
- Es interactivo en el bloque de desarrollo: pregunta nombre/email de git si faltan, crea la clave SSH (pide passphrase) y abre el login de GitHub en el navegador.
- Crea una carpeta `logs/` junto al script con dos archivos por ejecución: `postinstall-<fecha>.log` (todo) y `errores-<fecha>.log` (solo comandos que fallaron y avisos, con el paso y el código de salida; si no hubo ninguno, no se deja).
- Al terminar, reinicia: `sudo reboot`.

> Lee el script antes de ejecutarlo.

## Qué hace

1. Acelera DNF (descargas en paralelo) y actualiza el sistema.
2. Agrega **RPM Fusion** (free + nonfree) y habilita el códec H.264 de Cisco.
3. Habilita **Flathub** completo y desactiva el remoto `fedora` de Flatpak (una sola fuente).
4. Instala **códecs multimedia** completos (`ffmpeg`, GStreamer) y **aceleración de video** según la GPU:
   - Intel → `intel-media-driver`
   - AMD → drivers `freeworld` de Mesa
5. Si `/` es **Btrfs**, configura **snapper** (snapshots con límites conservadores) para poder volver atrás si una actualización rompe algo.
6. Actualiza el **firmware** (BIOS, EC, SSD…) vía fwupd/LVFS.
7. **CLI** (`DO_CLI`): btop, htop, fastfetch, ncdu, ripgrep, fd, fzf, bat, eza, zoxide, jq, curl, wget, unzip, 7zip, rsync, tree; **ghostty** y **starship** (COPR) con `starship init` en `~/.bashrc`. Ghostty queda con tema **Gruvbox** (Light en modo claro, Dark en oscuro), 10 % de transparencia (`background-opacity = 0.9`), ventana inicial de 110×32 (para que quepa fastfetch) y CaskaydiaCove Nerd Font; el prompt de **Starship** es minimalista, de una línea (icono de Fedora, `usuario@equipo`, ruta, rama de git), al estilo `catppuccin_mocha` de oh-my-posh, y toma los colores del tema claro/oscuro de Ghostty (para cambiar de tema basta editar `theme` en la config de Ghostty). **fastfetch** con el logo grande de Fedora y 16 módulos con iconos (sistema, hardware, batería…) (`~/.config/fastfetch/config.jsonc`). Si ya tienes ajustes propios (`starship.toml`, config de fastfetch, claves en la config de Ghostty), no se sobrescriben.
8. **Desarrollo** (`DO_DEV`): git, gh, `development-tools`, nvm + Node LTS, pnpm y Claude Code globales, [gentle-ai](https://github.com/Gentleman-Programming/gentle-ai) (solo el binario; la configuración de agentes la haces tú con `gentle-ai`), clave SSH ed25519 subida a GitHub con `gh`.
9. **Juegos** (`DO_GAMING`): Steam, GameMode y MangoHud nativos.
10. **Navegadores** (`DO_BROWSERS`): Google Chrome (repo oficial de Google) y **Helium** (COPR oficial `imput/helium`, paquete `helium-bin`), que queda como navegador **predeterminado**. Quita Brave, Vivaldi y Zen (y sus repos) si los instaló una versión anterior del script, sin borrar sus datos. Firefox se deja.
11. **Apps** (`DO_APPS`): LibreOffice (dnf); Flatpak: Zed, VSCodium, PhpStorm, DataGrip, WebStorm, IntelliJ IDEA, Spotify, Discord, VLC, Bitwarden, Obsidian, Bruno, Flatseal.
12. **Fuentes e iconos** (`DO_FONTS`): CaskaydiaCove Nerd Font (Cascadia Code) y Outfit en `~/.local/share/fonts`; paquete `papirus-icon-theme`.
13. **Cursor, ajustes y extensiones de GNOME** (`DO_APPEARANCE`): compila el cursor **Mocu** blanco (commit fijado) en `~/.local/share/icons` e instala `xcursorgen`, `librsvg2-tools` y `xmlstarlet`. Con sesión de GNOME aplica por `gsettings`: iconos Papirus, cursor Mocu-White-Right, fuente Outfit 12 y monoespaciada CaskaydiaCove Nerd Font 12. También instala y activa las extensiones Vitals, RunCat, AppIndicator y Dashcraft desde extensions.gnome.org (aparecen al reiniciar sesión). Ver [docs/despues-del-script.md](docs/despues-del-script.md#iconos-y-cursores).
14. Activa `fstrim.timer`.

Interruptores al inicio del script: `DO_SNAPSHOTS`, `DO_FIRMWARE`, `DO_CLI`, `DO_DEV`, `DO_GAMING`, `DO_BROWSERS`, `DO_APPS`, `DO_FONTS`, `DO_APPEARANCE`.

## Qué NO hace (a propósito)

- En el escritorio solo toca iconos, cursor, fuentes y las 4 extensiones indicadas. No instala temas GTK ni de shell.
- No instala contenedores (Docker/Podman) ni servidores de base de datos.
- No instala el driver propietario de NVIDIA. Ver [docs/nvidia.md](docs/nvidia.md).
- No ejecuta `dnf autoremove`, que puede borrar drivers marcados como dependencia.

## Después del script

- [docs/despues-del-script.md](docs/despues-del-script.md) — configurar Steam, mantenimiento semanal y extras opcionales (Docker).
- [docs/nvidia.md](docs/nvidia.md) — solo si el equipo tiene GPU NVIDIA.

## Limitaciones

- Solo Fedora con `dnf` (Workstation). **No** sirve en Fedora Atomic (Silverblue, Kinoite, Bazzite), que usa `rpm-ostree`.
- Probado en Fedora 45 con GPU Intel. Las ramas de AMD y los bloques de CLI, desarrollo, juegos, navegadores y apps no se han ejecutado todavía. El bloque de cursor y ajustes de GNOME no se ha ejecutado completo tras el último recorte.
- ghostty y starship dependen de repos COPR de terceros (Helium usa el COPR de su propio proyecto): pueden no tener build para tu versión de Fedora.
- Los nombres de paquetes pueden cambiar entre versiones de Fedora. El script no se detiene por un fallo puntual; revisa el log.
