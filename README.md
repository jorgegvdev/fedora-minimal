# fedora-minimal

Post-instalación **mínima** para Fedora Workstation. Deja el sistema funcional, actualizado y estable, y nada más: el escritorio, las apps y los ajustes los configuras tú después.

Sirve en cualquier equipo y con cualquier escritorio (KDE, GNOME, XFCE…), porque detecta el hardware en vez de asumirlo.

## Uso

En una instalación limpia de Fedora (no necesita `git`):

```bash
curl -fsSL https://raw.githubusercontent.com/jorgegvdev/fedora-minimal/main/fedora-postinstall.sh -o fedora-postinstall.sh
bash fedora-postinstall.sh
```

- Ejecútalo como usuario normal, **no** con `sudo`. Pide tu contraseña una vez.
- Es seguro volver a ejecutarlo.
- Crea una carpeta `logs/` junto al script con dos archivos por ejecución: `postinstall-<fecha>.log` (todo) y `errores-<fecha>.log` (solo comandos que fallaron y avisos, con el paso y el código de salida; si no hubo ninguno, no se deja).
- Al terminar, reinicia: `sudo reboot`.

> Lee el script antes de ejecutarlo; son ~120 líneas.

## Qué hace

1. Acelera DNF (descargas en paralelo) y actualiza el sistema.
2. Agrega **RPM Fusion** (free + nonfree) y habilita el códec H.264 de Cisco.
3. Habilita **Flathub** completo y desactiva el remoto `fedora` de Flatpak (una sola fuente).
4. Instala **códecs multimedia** completos (`ffmpeg`, GStreamer) y **aceleración de video** según la GPU:
   - Intel → `intel-media-driver`
   - AMD → drivers `freeworld` de Mesa
5. Si `/` es **Btrfs**, configura **snapper** (snapshots con límites conservadores) para poder volver atrás si una actualización rompe algo.
6. Actualiza el **firmware** (BIOS, EC, SSD…) vía fwupd/LVFS.
7. Activa `fstrim.timer`.

Interruptores al inicio del script: `DO_SNAPSHOTS` y `DO_FIRMWARE`.

## Qué NO hace (a propósito)

- No toca el escritorio: sin extensiones, temas ni ajustes.
- No instala apps (navegador, ofimática, juegos, herramientas de desarrollo…).
- No instala el driver propietario de NVIDIA. Ver [docs/nvidia.md](docs/nvidia.md).
- No ejecuta `dnf autoremove`, que puede borrar drivers marcados como dependencia.

## Después del script

- [docs/despues-del-script.md](docs/despues-del-script.md) — programación y juegos ligeros, comandos sueltos para copiar cuando los quieras.
- [docs/nvidia.md](docs/nvidia.md) — solo si el equipo tiene GPU NVIDIA.

## Limitaciones

- Solo Fedora con `dnf` (Workstation, KDE, XFCE…). **No** sirve en Fedora Atomic (Silverblue, Kinoite, Bazzite), que usa `rpm-ostree`.
- Probado en Fedora 45 con GPU Intel. Las ramas de AMD no se han ejecutado.
- Los nombres de paquetes pueden cambiar entre versiones de Fedora. El script no se detiene por un fallo puntual; revisa el log.
