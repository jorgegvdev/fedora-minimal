# Después del script

Lo que el script no hace por ti.

## Steam

En Steam: *Configuración → Compatibilidad* → activa "Habilitar Steam Play para todos los demás títulos". Si un juego falla, prueba otra versión de Proton (o Proton-GE con `net.davidotek.pupgui2` en Flatpak) antes de tocar el sistema.

Opción de lanzamiento para ver FPS y mejorar rendimiento:
```
gamemoderun mangohud %command%
```

**Para evitar problemas:**
- No pongas la biblioteca de Steam en una partición NTFS; Proton falla o corre mal.
- Antes de comprar un juego online, revisa su anticheat en [ProtonDB](https://www.protondb.com).
- Steam, GameMode y MangoHud van todos nativos. Mezclar versiones Flatpak y nativas puede romper el overlay y Proton.

## Iconos y cursores

El script ya aplica Papirus (iconos) y `Mocu-White-Right` (cursor) con `gsettings`. Para cambiarlos: **Retoques** → *Apariencia*.

Si el cursor se ve pequeño: `gsettings set org.gnome.desktop.interface cursor-size 32`.

## Extras opcionales

**Docker Engine** (no lo instala el script; revisa https://docs.docker.com/engine/install/fedora/ por si cambió):
```bash
sudo dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```
Cierra sesión y vuelve a entrar. El grupo `docker` equivale a acceso root: está bien en un equipo personal, no en uno compartido.

- **SELinux:** al montar carpetas en un contenedor agrega `:Z` (`-v ./data:/data:Z`) o dará "permission denied". No desactives SELinux.
- **Alternativa:** Fedora trae **Podman**, compatible con comandos Docker y sin demonio.

## Mantenimiento semanal

```bash
sudo dnf upgrade --refresh
flatpak update
sudo fwupdmgr get-updates
```

Si una actualización rompe algo, restaura un snapshot con **Btrfs Assistant** (o arranca el kernel anterior desde el menú de GRUB).

Evita `sudo dnf autoremove` a ciegas: revisa primero qué va a quitar.
