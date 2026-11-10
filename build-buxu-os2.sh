#!/usr/bin/env bash
# BUXU OS - script de construção da ISO (base Debian 13 "trixie" + LXQt)
# Rode em um Debian/Ubuntu com internet:  sudo bash build-buxu-os.sh
# Precisa de ~15 GB livres. Demora de 30 a 90 minutos. A ISO sai em ./buxu-build/
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

# ---------- Pacotes ----------
cat > config/package-lists/buxu.list.chroot <<'EOF'
# Base gráfica leve
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

# Loja de programas (apt + Flatpak, instala com um clique)
gnome-software
gnome-software-plugin-flatpak
flatpak
packagekit

# Pendrives e discos (montagem automática), monitor de recursos
udisks2
gvfs
gvfs-backends
qps
htop

# Relógio ajustado pela internet e memória comprimida (zram)
chrony
zram-tools

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
locales-all
plymouth

# Instalador (Calamares) e ferramentas para instalar no disco
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

# ---------- Relógio: corrige a hora mesmo se estiver muito errada ----------
mkdir -p config/includes.chroot/etc/chrony/conf.d
cat > config/includes.chroot/etc/chrony/conf.d/buxu.conf <<'EOF'
makestep 1 -1
EOF

# ---------- Memória comprimida (zram) ----------
cat > config/includes.chroot/etc/default/zramswap <<'EOF'
ALGO=zstd
PERCENT=100
PRIORITY=100
EOF

# ---------- Touchpads I2C: carregar módulos comuns ----------
mkdir -p config/includes.chroot/etc/modules-load.d
cat > config/includes.chroot/etc/modules-load.d/buxu-input.conf <<'EOF'
i2c_hid_acpi
hid_multitouch
EOF

# ---------- Idioma padrão: português do Brasil ----------
cat > config/includes.chroot/etc/default/locale <<'EOF'
LANG=pt_BR.UTF-8
LANGUAGE=pt_BR:pt:en
LC_MESSAGES=pt_BR.UTF-8
EOF

# ---------- Loja de programas sem pedir senha (instalar/remover programas) ----------
mkdir -p config/includes.chroot/etc/polkit-1/rules.d
cat > config/includes.chroot/etc/polkit-1/rules.d/49-buxu-loja.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if ((action.id.indexOf("org.freedesktop.packagekit.") == 0 ||
         action.id.indexOf("org.freedesktop.Flatpak.") == 0) &&
        subject.local && subject.active) {
        return polkit.Result.YES;
    }
});
EOF

# ---------- Calamares sem pedir senha no modo Live ----------
cat > config/includes.chroot/etc/sudoers.d/buxu-calamares <<'EOF'
buxu ALL=(ALL) NOPASSWD: /usr/bin/calamares
EOF
chmod 0440 config/includes.chroot/etc/sudoers.d/buxu-calamares

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

# ---------- Atalho "Instalar BUXU OS" nativo no modelo do esqueleto (/etc/skel) ----------
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

# ---------- Modo live: login automático ----------
mkdir -p config/includes.chroot/usr/local/sbin config/includes.chroot/etc/systemd/system
cat > config/includes.chroot/usr/local/sbin/buxu-live-setup <<'EOF'
#!/bin/bash
U=buxu
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-buxu.conf <<EOC
[Seat:*]
autologin-user=$U
autologin-user-timeout=0
autologin-session=lxqt
EOC

H=/home/$U
if [ -d "$H" ]; then
    mkdir -p "$H/Desktop"
    cp /etc/skel/Desktop/buxu-instalar.desktop "$H/Desktop/"
    chmod +x "$H/Desktop/buxu-instalar.desktop"
    chown -R $U:$U "$H/Desktop" 2>/dev/null || true
fi
exit 0
EOF
chmod +x config/includes.chroot/usr/local/sbin/buxu-live-setup
cat > config/includes.chroot/etc/systemd/system/buxu-live-setup.service <<'EOF'
[Unit]
Description=BUXU OS - ajustes do modo live
ConditionKernelCommandLine=boot=live
After=live-config.service
Before=display-manager.service lightdm.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/buxu-live-setup

[Install]
WantedBy=multi-user.target
EOF

# ---------- Sistema instalado: GRUB discreto e oculto ----------
cat > config/includes.chroot/etc/default/grub <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR="BUXU OS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3"
GRUB_CMDLINE_LINUX=""
EOF

# ---------- Tela do porco fica visível por 8 segundos no Live e 2s Instalado ----------
mkdir -p config/includes.chroot/etc/systemd/system/plymouth-quit.service.d
cat > config/includes.chroot/etc/systemd/system/plymouth-quit.service.d/buxu-atraso.conf <<'EOF'
[Service]
ExecStartPre=/bin/sh -c 'if grep -q boot=live /proc/cmdline; then sleep 8; else sleep 2; fi'
EOF

# ---------- Imagens do porco (ícone do menu e tela de boot) ----------
mkdir -p config/includes.chroot/usr/share/icons/buxu
mkdir -p config/includes.chroot/usr/share/plymouth/themes/buxu

base64 -d > config/includes.chroot/usr/share/icons/buxu/porco.png <<'B64'
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
BGeI5M3k9Vt2CexWvx+B1PsQAhU0qpm轨
cat > build-buxu-os.sh <<'EOF'
#!/usr/bin/env bash
# BUXU OS - script de construção da ISO (base Debian 13 "trixie" + LXQt)
# Rode em um Debian/Ubuntu com internet:  sudo bash build-buxu-os.sh
# Precisa de ~15 GB livres. Demora de 30 a 90 minutos. A ISO sai em ./buxu-build/
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

lb config   --mode debian   --initsystem systemd   --distribution trixie   --linux-flavours amd64   --linux-packages "linux-image"   --mirror-bootstrap "http://deb.debian.org/debian/"   --mirror-chroot "http://deb.debian.org/debian/"   --mirror-binary "http://deb.debian.org/debian/"   --security false   --firmware-chroot false   --firmware-binary false   --architectures amd64   --archive-areas "main contrib non-free non-free-firmware"   --binary-images iso-hybrid   --memtest none   --iso-application "BUXU OS"   --iso-publisher "BUXU OS"   --iso-volume "BUXU_OS"   --bootappend-live "boot=live components quiet splash loglevel=3 vt.global_cursor_default=0 locales=pt_BR.UTF-8 keyboard-layouts=br timezone=America/Fortaleza hostname=buxu username=buxu"

mkdir -p config/archives
echo "deb http://deb.debian.org/debian-security trixie-security main contrib non-free non-free-firmware" > config/archives/security.list.chroot
cp config/archives/security.list.chroot config/archives/security.list.binary

mkdir -p config/package-lists config/hooks/normal          config/includes.chroot/etc/X11/xorg.conf.d          config/includes.chroot/etc/lightdm/lightdm.conf.d          config/includes.chroot/etc/default          config/includes.chroot/etc/skel/Desktop

# ---------- Pacotes ----------
cat > config/package-lists/buxu.list.chroot <<'EOF'
# Base gráfica leve
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

# Loja de programas (apt + Flatpak, instala com um clique)
gnome-software
gnome-software-plugin-flatpak
flatpak
packagekit

# Pendrives e discos (montagem automática), monitor de recursos
udisks2
gvfs
gvfs-backends
qps
htop

# Relógio ajustado pela internet e memória comprimida (zram)
chrony
zram-tools

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
locales-all
plymouth

# Instalador (Calamares) e ferramentas para instalar no disco
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

# ---------- Relógio: corrige a hora mesmo se estiver muito errada ----------
mkdir -p config/includes.chroot/etc/chrony/conf.d
cat > config/includes.chroot/etc/chrony/conf.d/buxu.conf <<'EOF'
makestep 1 -1
EOF

# ---------- Memória comprimida (zram) ----------
cat > config/includes.chroot/etc/default/zramswap <<'EOF'
ALGO=zstd
PERCENT=100
PRIORITY=100
EOF

# ---------- Touchpads I2C: carregar módulos comuns ----------
mkdir -p config/includes.chroot/etc/modules-load.d
cat > config/includes.chroot/etc/modules-load.d/buxu-input.conf <<'EOF'
i2c_hid_acpi
hid_multitouch
EOF

# ---------- Idioma padrão: português do Brasil ----------
cat > config/includes.chroot/etc/default/locale <<'EOF'
LANG=pt_BR.UTF-8
LANGUAGE=pt_BR:pt:en
LC_MESSAGES=pt_BR.UTF-8
EOF

# ---------- Loja de programas sem pedir senha (instalar/remover programas) ----------
mkdir -p config/includes.chroot/etc/polkit-1/rules.d
cat > config/includes.chroot/etc/polkit-1/rules.d/49-buxu-loja.rules <<'EOF'
polkit.addRule(function(action, subject) {
    if ((action.id.indexOf("org.freedesktop.packagekit.") == 0 ||
         action.id.indexOf("org.freedesktop.Flatpak.") == 0) &&
        subject.local && subject.active) {
        return polkit.Result.YES;
    }
});
EOF

# ---------- Calamares sem pedir senha no modo Live ----------
cat > config/includes.chroot/etc/sudoers.d/buxu-calamares <<'EOF'
buxu ALL=(ALL) NOPASSWD: /usr/bin/calamares
EOF
chmod 0440 config/includes.chroot/etc/sudoers.d/buxu-calamares

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

# ---------- Atalho "Instalar BUXU OS" nativo no modelo do esqueleto (/etc/skel) ----------
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

# ---------- Modo live: login automático ----------
mkdir -p config/includes.chroot/usr/local/sbin config/includes.chroot/etc/systemd/system
cat > config/includes.chroot/usr/local/sbin/buxu-live-setup <<'EOF'
#!/bin/bash
U=buxu
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-buxu.conf <<EOC
[Seat:*]
autologin-user=$U
autologin-user-timeout=0
autologin-session=lxqt
EOC

H=/home/$U
if [ -d "$H" ]; then
    mkdir -p "$H/Desktop"
    cp /etc/skel/Desktop/buxu-instalar.desktop "$H/Desktop/"
    chmod +x "$H/Desktop/buxu-instalar.desktop"
    chown -R $U:$U "$H/Desktop" 2>/dev/null || true
fi
exit 0
EOF
chmod +x config/includes.chroot/usr/local/sbin/buxu-live-setup
cat > config/includes.chroot/etc/systemd/system/buxu-live-setup.service <<'EOF'
[Unit]
Description=BUXU OS - ajustes do modo live
ConditionKernelCommandLine=boot=live
After=live-config.service
Before=display-manager.service lightdm.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/buxu-live-setup

[Install]
WantedBy=multi-user.target
EOF

# ---------- Sistema instalado: GRUB discreto e oculto ----------
cat > config/includes.chroot/etc/default/grub <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR="BUXU OS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3"
GRUB_CMDLINE_LINUX=""
EOF

# ---------- Tela do porco fica visível por 8 segundos no Live e 2s Instalado ----------
mkdir -p config/includes.chroot/etc/systemd/system/plymouth-quit.service.d
cat > config/includes.chroot/etc/systemd/system/plymouth-quit.service.d/buxu-atraso.conf <<'EOF'
[Service]
ExecStartPre=/bin/sh -c 'if grep -q boot=live /proc/cmdline; then sleep 8; else sleep 2; fi'
EOF

# ---------- Imagens do porco (ícone do menu e tela de boot) ----------
mkdir -p config/includes.chroot/usr/share/icons/buxu
mkdir -p config/includes.chroot/usr/share/plymouth/themes/buxu

base64 -d > config/includes.chroot/usr/share/icons/buxu/porco.png <<'B64'
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
BGeI5M3k9Vt2CexWvx+B1PsQAhU0qpm轨
cat >> build-buxu-os.sh <<'EOF'
B64

base64 -d > config/includes.chroot/usr/share/plymouth/themes/buxu/porco.png <<'B64'
iVBORw0KGgoAAAANSUhEUgAAASwAAADkCAMAAAAVb+kqAAABIFBMVEWkX2PomaGpnJvLYmnX09Fn
WVgjISNTISPi6enl7epbPUHaeIYqTmYeNEzYvMGfe4Hi7Oitsa9TQT218u2Tgn3Qwr2txLY1Rjp7
fny5zsUA/wBsh3h5jYWPPUV///8A//+KNjmv4bT//wD/AAD/sfc5YlELIxgELxYuZo14eoV4nYy8
vMD09K9zqZe549P/f3//sbEABAAAAP8eSzZvlHl//39j7Kg4VTg/v39FdFpjhW5gjXe/v3+ItJ68
3tT/f////38AAADzwcHvu7z0vcHzwb79/v731tf6+/oLAwT25ucrFxczJyfStrdLNzf1+vj5/Pv0
9/bulJtsV1dUR0eNdnfz9/Wvl5cpBwjLqKr1+fj0+PdzZmf73OGyp6eTh4etn/LgAAAAYHRSTlP+
//7//P7+/hJg/v/+//7+lQb+CP7++vwE9wH39v8CAf8JAQEDXh6h//9l/wQXZgIDaAFNHAIFCQSk
RYkEsb8CAgD/////Bf70/v3+/v7+MNJO//7+/m/+/v6wkP7+/v4zeLrwAAA5gElEQVR42u2dCX+j
SJLoEUWC7eqy667u6Wt6do7d2dn7ePfhBJRkkmC7ACNsEN//W7yIyARJtiRLLrvs+fWjuw67ZEn8
FREZERkR6Zzudk2H6/RXfDm7kTo7u6Dr7OzXzMvZCdXF9bm9rgDYrxbX3bDeAKokSTy64C/JFeD6
+f/DWi9W1+eJN2e5L339tp17CnD9SpXRuYvVwXWi6lKXlVvX71mZ52WtkqvLX6UuOnezOi7zIhPC
g/+VaKpSMzdJrn+NtJy7dDCZ6zxTIuY8DDnnQqmsTJn6VdLaBus3v4BcuZoJIQAUogoRWNv6v/R+
jbScjQ7o6ZRYpW0nogDicRwSqjCKvCTT+tdIy9nirKMOpkUnAFEMV2glizc88QrfRVq/bljT6e8P
Fqxc3QpuUYVgtvAKIxFmImZvQbZ+ZaLl3JKps4srui6vE0/nXYeyBLh4xBdXxgXXbXJ+dvCrhTU9
gBDw6vw8oQtc0VZnXUOWnURqsPBhKHim+tT9tYmWs+IoECnlHc/dbO4lbdqoBsXKwqI/IzJbQE6V
pTq/+BJa07+2VIazwgpIzdsySHWu81LLShGWQbRApCKkRS5X2GUgWlf3VkRU+PH6K+HlrLDyXJaz
ygVx8kSdknEHQJExV2EWEi6khdA6Jycb//N9SB2cXVyej9flxV8FrwHWfxArpku3Ux2QUV6praEa
BMupoSA603XwsqvLq3tD
EOF
