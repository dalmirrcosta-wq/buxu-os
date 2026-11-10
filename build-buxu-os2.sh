#!/usr/bin/env bash
# BUXU OS - script de construção da ISO (base Debian 13 "trixie" + LXQt)
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Rode com sudo: sudo bash $0"; exit 1
fi

apt-get update
apt-get install -y live-build debootstrap xorriso squashfs-tools debian-archive-keyring ca-certificates mtools dosfstools cpio

WORK="${PWD}/buxu-build"
mkdir -p "$WORK"
cd "$WORK"
lb clean --purge 2>/dev/null || true

lb config \
  --mode debian \
  --initsystem systemd \
  --distribution trixie \
  --linux-flavours amd64 \
  --linux-packages "linux-image" \
  --mirror-bootstrap "http://deb.debian.org/debian/" \
  --mirror-chroot "http://deb.debian.org/debian/" \
  --mirror-binary "http://deb.debian.org/debian/" \
  --security false \
  --firmware-chroot false \
  --firmware-binary false \
  --architectures amd64 \
  --archive-areas "main contrib non-free non-free-firmware" \
  --binary-images iso-hybrid \
  --memtest none \
  --iso-application "BUXU OS" \
  --iso-publisher "BUXU OS" \
  --iso-volume "BUXU_OS" \
  --bootappend-live "boot=live components quiet splash loglevel=3 vt.global_cursor_default=0 locales=pt_BR.UTF-8 keyboard-layouts=br timezone=America/Fortaleza hostname=buxu username=buxu"

mkdir -p config/archives
echo "deb http://deb.debian.org/debian-security trixie-security main contrib non-free non-free-firmware" > config/archives/security.list.chroot
cp config/archives/security.list.chroot config/archives/security.list.binary

mkdir -p config/package-lists config/hooks/normal \
         config/includes.chroot/etc/X11/xorg.conf.d \
         config/includes.chroot/etc/lightdm/lightdm.conf.d \
         config/includes.chroot/etc/default \
         config/includes.chroot/etc/skel/Desktop

# ---------- Lista de Pacotes ----------
cat > config/package-lists/buxu.list.chroot <<'EOF'
xorg
lightdm
lightdm-gtk-greeter
lxqt-core
lxqt-policykit
lxqt-archiver
featherpad
galculator
vlc
fonts-noto-core
fonts-dejavu
papirus-icon-theme
xdg-user-dirs
gnome-software
gnome-software-plugin-flatpak
flatpak
packagekit
udisks2
gvfs
gvfs-backends
qps
htop
chrony
zram-tools
network-manager
network-manager-gnome
pipewire
pipewire-pulse
pipewire-alsa
wireplumber
alsa-utils
pavucontrol-qt
firmware-sof-signed
mesa-vulkan-drivers
intel-media-va-driver
xserver-xorg-input-libinput
libinput-tools
xserver-xorg-video-fbdev
xserver-xorg-video-vesa
firmware-linux
firmware-misc-nonfree
firmware-iwlwifi
firmware-realtek
firmware-atheros
firmware-brcm80211
intel-microcode
locales
locales-all
plymouth

# Instalador e Suporte a Discos
calamares
calamares-settings-debian
grub-common
grub-pc-bin
grub-efi-amd64-bin
grub-efi-amd64-signed
shim-signed
efibootmgr
os-prober
dosfstools
e2fsprogs
ntfs-3g
cryptsetup
parted
console-setup
keyboard-configuration
sudo
curl
gnupg
extrepo
EOF

# ---------- Idioma e Teclado ----------
cat > config/includes.chroot/etc/default/locale <<'EOF'
LANG=pt_BR.UTF-8
LANGUAGE=pt_BR:pt:en
LC_MESSAGES=pt_BR.UTF-8
EOF

cat > config/includes.chroot/etc/default/keyboard <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="br"
XKBVARIANT="abnt2"
XKBOPTIONS=""
BACKSPACE="guess"
EOF

# ---------- Sudoers para o Calamares (sem senha no modo Live) ----------
mkdir -p config/includes.chroot/etc/sudoers.d
cat > config/includes.chroot/etc/sudoers.d/buxu-calamares <<'EOF'
buxu ALL=(ALL) NOPASSWD: /usr/bin/calamares
EOF
chmod 0440 config/includes.chroot/etc/sudoers.d/buxu-calamares

# ---------- Atalho "Instalar BUXU OS" no esqueleto e no Desktop ----------
cat > config/includes.chroot/etc/skel/Desktop/buxu-instalar.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=Instalar BUXU OS
Name[pt_BR]=Instalar BUXU OS
Comment=Instalar o BUXU OS no disco do computador
Exec=sudo /usr/bin/calamares
Icon=system-software-install
Terminal=false
Categories=System;
EOF
chmod +x config/includes.chroot/etc/skel/Desktop/buxu-instalar.desktop

# ---------- Hook de Execução no Boot Live (Garante o atalho na área de trabalho) ----------
mkdir -p config/includes.chroot/lib/live/config
cat > config/includes.chroot/lib/live/config/9999-buxu-desktop <<'EOF'
#!/bin/sh
# Força a cópia do atalho para o usuário live no momento do login
mkdir -p /home/buxu/Desktop
cp /etc/skel/Desktop/buxu-instalar.desktop /home/buxu/Desktop/
chmod +x /home/buxu/Desktop/buxu-instalar.desktop
chown -R buxu:buxu /home/buxu/Desktop
EOF
chmod +x config/includes.chroot/lib/live/config/9999-buxu-desktop

# ---------- Atraso no Plymouth (8s no Live) ----------
mkdir -p config/includes.chroot/etc/systemd/system/plymouth-quit.service.d
cat > config/includes.chroot/etc/systemd/system/plymouth-quit.service.d/buxu-atraso.conf <<'EOF'
[Service]
ExecStartPre=/bin/sh -c 'if grep -q boot=live /proc/cmdline; then sleep 8; else sleep 2; fi'
EOF

# ---------- REESCREVE O GERENCIADOR DE BOOT (REMOVE A TELA AMARELA DO GRUB) ----------
mkdir -p config/bootloaders/grub-pc
cat > config/bootloaders/grub-pc/grub.cfg <<'EOF'
set default=0
set timeout=0

menuentry "BUXU OS Live" {
    linux /live/vmlinuz boot=live components quiet splash loglevel=3 vt.global_cursor_default=0 locales=pt_BR.UTF-8 keyboard-layouts=br timezone=America/Fortaleza hostname=buxu username=buxu
    initrd /live/initrd.img
}
EOF

# ---------- Construção da ISO ----------
lb build 2>&1 | tee build.log