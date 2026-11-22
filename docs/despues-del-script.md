# Después del script

Comandos sueltos para lo que el script no instala. Copia solo lo que necesites.

## Programar

**Herramientas de compilación** (algunos paquetes de npm compilan código nativo):
```bash
sudo dnf group install development-tools
```

**Git**:
```bash
sudo dnf install git
git config --global user.name "Tu Nombre"
git config --global user.email "tu@email.com"
git config --global init.defaultBranch main
```

**Clave SSH** (GitHub/GitLab):
```bash
ssh-keygen -t ed25519 -C "tu@email.com"
cat ~/.ssh/id_ed25519.pub
```

**Node con nvm** (no está en los repos de Fedora; revisa la última versión en https://github.com/nvm-sh/nvm/releases):
```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash
```
Abre una terminal nueva y:
```bash
nvm install --lts
nvm alias default 'lts/*'
```

**Docker Engine** (repo oficial; revisa https://docs.docker.com/engine/install/fedora/ por si cambió):
```bash
sudo dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker $USER
```
Cierra sesión y vuelve a entrar. El grupo `docker` equivale a acceso root: está bien en un equipo personal, no en uno compartido.

- **SELinux:** al montar carpetas en un contenedor agrega `:Z` (`-v ./data:/data:Z`) o dará "permission denied". No desactives SELinux.
- **Alternativa:** Fedora trae **Podman**, compatible con comandos Docker y sin demonio.

**VS Code** (repo de Microsoft, nativo para que su terminal vea Node, Docker y git):
```bash
sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
sudo dnf install code
```

**Base de datos en contenedor** (ejemplo PostgreSQL, solo desarrollo local):
```bash
docker run -d --name pg -e POSTGRES_PASSWORD=cambiame -p 5432:5432 -v pgdata:/var/lib/postgresql/data postgres:17
```

## Juegos ligeros

Regla: **Steam, GameMode y MangoHud van todos nativos**. Mezclar versiones Flatpak y nativas puede romper el overlay y Proton.

```bash
sudo dnf install steam gamemode mangohud
sudo usermod -aG gamemode $USER
```

En Steam: *Configuración → Compatibilidad* → activa "Habilitar Steam Play para todos los demás títulos". Si un juego falla, prueba otra versión de Proton (o Proton-GE con `net.davidotek.pupgui2` en Flatpak) antes de tocar el sistema.

Opción de lanzamiento en Steam para ver FPS y mejorar rendimiento:
```
gamemoderun mangohud %command%
```

**Para evitar problemas:**
- No pongas la biblioteca de Steam en una partición NTFS; Proton falla o corre mal.
- Antes de comprar un juego online, revisa su anticheat en [ProtonDB](https://www.protondb.com).

## Apps por Flatpak

Apps gráficas de usuario que se benefician de estar aisladas y al día (Flathub ya está habilitado por el script):
```bash
flatpak install flathub com.spotify.Client com.discordapp.Discord
```

Regla general: lo que toca hardware, drivers o desarrollo, nativo (`dnf`); apps de usuario, Flatpak.

## Mantenimiento semanal

```bash
sudo dnf upgrade --refresh
flatpak update
sudo fwupdmgr get-updates
```

Si una actualización rompe algo, restaura un snapshot con **Btrfs Assistant** (o arranca el kernel anterior desde el menú de GRUB).

Evita `sudo dnf autoremove` a ciegas: revisa primero qué va a quitar.
