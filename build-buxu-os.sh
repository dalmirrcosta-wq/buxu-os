#!/usr/bin/env bash
# BUXU OS - script de construção da ISO (base Debian 13 "trixie" + LXQt)
# Rode em um Debian/Ubuntu com internet:  sudo bash build-buxu-os.sh
# Precisa de ~15 GB livres. Demora de 30 a 90 minutos. A ISO sai em ./buxu-build/
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
  echo "Rode com sudo: sudo bash $0"; exit 1
fi

apt-get update
apt-get install -y live-build debootstrap xorriso squashfs-tools debian-archive-keyring ca-certificates

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
  --debian-installer none \
  --memtest none \
  --iso-application "BUXU OS" \
  --iso-publisher "BUXU OS" \
  --iso-volume "BUXU_OS" \
  --bootappend-live "boot=live components quiet locales=pt_BR.UTF-8 keyboard-layouts=br timezone=America/Fortaleza hostname=buxu username=buxu"

mkdir -p config/archives
echo "deb http://deb.debian.org/debian-security trixie-security main contrib non-free non-free-firmware" > config/archives/security.list.chroot
cp config/archives/security.list.chroot config/archives/security.list.binary

mkdir -p config/package-lists config/hooks/normal \
         config/includes.chroot/etc/X11/xorg.conf.d \
         config/includes.chroot/etc/sddm.conf.d \
         config/includes.chroot/etc/default

# ---------- Pacotes ----------
cat > config/package-lists/buxu.list.chroot <<'EOF'
# Base gráfica leve
xorg
sddm
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

# Loja de programas (apt + Flatpak, instala com um clique)
gnome-software
gnome-software-plugin-flatpak
flatpak
packagekit

# Rede (cabo e Wi-Fi)
network-manager
network-manager-gnome

# Som
pipewire
pipewire-pulse
pipewire-alsa
wireplumber
alsa-utils
pavucontrol-qt
firmware-sof-signed

# Vídeo, teclado, touchpad, USB
mesa-vulkan-drivers
intel-media-va-driver
xserver-xorg-input-libinput
libinput-tools
xserver-xorg-video-fbdev
xserver-xorg-video-vesa

# Firmwares (Wi-Fi e outros)
firmware-linux
firmware-misc-nonfree
firmware-iwlwifi
firmware-realtek
firmware-atheros
firmware-brcm80211
intel-microcode

# Idioma / sistema
locales
console-setup
keyboard-configuration
sudo
curl
gnupg
extrepo
EOF

# ---------- Teclado ABNT2 ----------
cat > config/includes.chroot/etc/default/keyboard <<'EOF'
XKBMODEL="pc105"
XKBLAYOUT="br"
XKBVARIANT="abnt2"
XKBOPTIONS=""
BACKSPACE="guess"
EOF

# ---------- Touchpad: toque para clicar, rolagem natural ----------
cat > config/includes.chroot/etc/X11/xorg.conf.d/40-libinput-touchpad.conf <<'EOF'
Section "InputClass"
    Identifier "BUXU touchpad"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
    Option "NaturalScrolling" "true"
    Option "DisableWhileTyping" "on"
EndSection
EOF

# ---------- Login automático ----------
cat > config/includes.chroot/etc/sddm.conf.d/autologin.conf <<'EOF'
[Autologin]
User=buxu
Session=lxqt.desktop
EOF

# ---------- Hook: personalizações feitas dentro do sistema ----------
cat > config/hooks/normal/0100-buxu.hook.chroot <<'EOF'
#!/bin/bash
set -e

# Português do Brasil
sed -i 's/^# *pt_BR.UTF-8 UTF-8/pt_BR.UTF-8 UTF-8/' /etc/locale.gen
grep -q '^pt_BR.UTF-8' /etc/locale.gen || echo 'pt_BR.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen
update-locale LANG=pt_BR.UTF-8 LANGUAGE=pt_BR:pt:en
ln -sf /usr/share/zoneinfo/America/Fortaleza /etc/localtime

# Identidade BUXU OS
cat > /etc/os-release <<OSR
PRETTY_NAME="BUXU OS"
NAME="BUXU OS"
VERSION="1.0"
ID=buxu
ID_LIKE=debian
HOME_URL="https://example.com/buxu"
OSR
echo "BUXU OS 1.0 \n \l" > /etc/issue

# LibreWolf (repositório oficial via extrepo)
extrepo enable librewolf
apt-get update
apt-get install -y librewolf || echo "AVISO: LibreWolf não instalou"

# Flathub na loja
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

# Limpeza
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF
chmod +x config/hooks/normal/0100-buxu.hook.chroot

# ---------- Construir ----------
lb build 2>&1 | tee build.log

ISO="$(ls -1 *.iso 2>/dev/null | head -n1 || true)"
if [ -n "$ISO" ]; then
  echo
  echo "Pronto! ISO gerada: $WORK/$ISO"
  echo "Teste no VirtualBox/QEMU ou grave no pendrive com Ventoy / balenaEtcher."
else
  echo "A ISO não foi gerada. Veja $WORK/build.log"; exit 1
fi
