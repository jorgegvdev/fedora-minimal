# NVIDIA (opcional)

Solo si el equipo tiene GPU NVIDIA. El script **no** instala esto. Requiere RPM Fusion, que el script ya agrega.

Fedora usa `akmod-nvidia`, que compila el módulo del kernel automáticamente en cada actualización de kernel.

## Secure Boot

- **Desactivado:** no hay que firmar nada. Es el camino simple.
- **Activado:** hay que firmar el módulo *antes* de instalar el driver (ver al final).

## Instalar

```bash
sudo dnf upgrade --refresh
sudo dnf install akmod-nvidia xorg-x11-drv-nvidia-cuda
sudo dnf mark user akmod-nvidia
```
`xorg-x11-drv-nvidia-cuda` trae `nvidia-smi` y las librerías de CUDA/NVENC. `mark user` evita que `dnf autoremove` borre el driver.

**No reinicies todavía.** El módulo tarda hasta ~5 minutos en compilarse. Comprueba:
```bash
modinfo -F version nvidia
```
Si muestra una versión (ej: `580.xx`), está listo; si dice "not found", espera y repite. Luego:
```bash
sudo reboot
```

## Laptop (suspensión y ahorro de energía)

```bash
sudo dnf install xorg-x11-drv-nvidia-power
sudo systemctl enable nvidia-suspend nvidia-resume nvidia-hibernate
```
Evita pantallas negras al suspender o despertar.

Video acelerado por VA-API sobre NVIDIA:
```bash
sudo dnf install libva-nvidia-driver
```

Para que la dGPU se apague cuando no se usa, crea `/etc/modprobe.d/nvidia.conf` con:
```
options nvidia NVreg_DynamicPowerManagement=0x02
```
Fuente: [RPM Fusion Optimus](https://rpmfusion.org/Howto/Optimus). Reinicia para aplicar.

## Usar la NVIDIA a demanda (laptop híbrida)

El escritorio usa la GPU Intel. Para ejecutar algo en la NVIDIA:
```bash
switcherooctl launch nombre-de-la-app
```
Opción de lanzamiento en Steam:
```
__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only %command%
```

## Verificar

```bash
nvidia-smi
mokutil --sb-state
```

## Después de actualizar el kernel

El módulo se recompila solo al arrancar el kernel nuevo. Si ves pantalla negra o `nouveau`:
```bash
sudo akmods --force
sudo dracut --force
```
Reinicia. Plan B: arranca el kernel anterior desde GRUB.

## Si usas Secure Boot

1. `sudo dnf install kmodtool akmods mokutil openssl`
2. `sudo kmodgenca -a` — genera la clave local de firma.
3. `sudo mokutil --import /etc/pki/akmods/certs/public_key.der` — pide una contraseña de un solo uso.
4. Reinicia y, en la pantalla azul MOK, elige *Enroll MOK* con esa contraseña (el teclado está en QWERTY).
5. Reinicia otra vez cuando lo pida.
6. Solo entonces instala o recompila `akmod-nvidia`.

Tras una actualización de BIOS/EFI puede hacer falta repetir el `mokutil --import`.

Fuente: [RPM Fusion NVIDIA](https://rpmfusion.org/Howto/NVIDIA).
