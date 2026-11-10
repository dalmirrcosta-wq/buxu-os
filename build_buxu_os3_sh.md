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
         config/includes.chroot/etc/default

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

# ---------- Modo live: login automático, atalho "Instalar BUXU OS" (não vai para o sistema instalado) ----------
mkdir -p config/includes.chroot/usr/local/sbin config/includes.chroot/etc/systemd/system
cat > config/includes.chroot/usr/local/sbin/buxu-live-setup <<'EOF'
#!/bin/bash
# Roda só no modo live, antes da tela de login
U=buxu
mkdir -p /etc/lightdm/lightdm.conf.d
cat > /etc/lightdm/lightdm.conf.d/50-buxu.conf <<EOC
[Seat:*]
autologin-user=$U
autologin-user-timeout=0
autologin-session=lxqt
EOC
cat > /usr/share/applications/buxu-instalar.desktop <<EOC
[Desktop Entry]
Type=Application
Name=Instalar BUXU OS
Name[pt_BR]=Instalar BUXU OS
Comment=Instalar o BUXU OS no disco do computador
Exec=sudo -E calamares
Icon=system-software-install
Terminal=false
Categories=System;
EOC
H=/home/$U
if [ -d "$H" ]; then
    mkdir -p "$H/Desktop"
    cp /usr/share/applications/buxu-instalar.desktop "$H/Desktop/"
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

# ---------- Sistema instalado: GRUB discreto e tela de boot do porco ----------
cat > config/includes.chroot/etc/default/grub <<'EOF'
GRUB_DEFAULT=0
GRUB_TIMEOUT_STYLE=hidden
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR="BUXU OS"
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash loglevel=3"
GRUB_CMDLINE_LINUX=""
EOF

# ---------- Tela do porco fica visível por mais tempo (8 s no live, 3 s instalado) ----------
mkdir -p config/includes.chroot/etc/systemd/system/plymouth-quit.service.d
cat > config/includes.chroot/etc/systemd/system/plymouth-quit.service.d/buxu-atraso.conf <<'EOF'
[Service]
ExecStartPre=/bin/sh -c 'if grep -q boot=live /proc/cmdline; then sleep 8; else sleep 3; fi'
EOF

# ---------- Imagens do porco (ícone do menu e tela de boot) ----------
mkdir -p config/includes.chroot/usr/share/icons/buxu
mkdir -p config/includes.chroot/usr/share/plymouth/themes/buxu

base64 -d > config/includes.chroot/usr/share/icons/buxu/porco.png <<'B64'
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
B64

cp config/includes.chroot/usr/share/icons/buxu/porco.png config/includes.chroot/usr/share/plymouth/themes/buxu/porco.png

base64 -d > config/includes.chroot/usr/share/plymouth/themes/buxu/dot.png <<'B64'
iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAABhklEQVR4nJ2SwWpTYRSE55xz/z9p
JdeVmwaJfQHfRIraCGoX3RYS6aMUW/AFTIWIhuKb+AI1iG6yKCaE3tz/nn9cNbgwBpzVLOZjDocR
AGB/bPLxhX87ertfWmuQM5448z4AmOi1Kr7MfXXx6P2b67us3JnvL8+fd2L7XdDiQeU1UnYAQFBD
2yJSbmaLujp5+GH4if2xCQD8eH3+9H6893nlDWpPDQQmEAEAggTh0ULRsgK/6uWz7mg4kZ+vLnqm
9jWolaucXCCGv4igtzRYyj737I9VIKed0CorrzdCACAQq7z2TmiVAjlVFRzceqKI6CZoDYvorSeq
4KDIkF7KLgLZxkEgkrKDkN7Wlk1SBadBjQS5LUyQQY0KTjUTVzsWhGTeCpJ5x4Jk4koJni3Sat62
aAT9H23etmiLtJoTPNO9y8G0YXMcrUDUYCSbP88mSJJN1GDRCjRsjvcuB1Nlf2zd0XByUy0PTWRW
xt0iarF+cdRCyrhbmMjsploedkfDyXpy/zPy358I2lNRXEw6AAAAAElFTkSuQmCC
B64

# ---------- Tela de boot: porco + bolinhas girando (estilo Windows 10) ----------
cat > config/includes.chroot/usr/share/plymouth/themes/buxu/buxu.plymouth <<'EOF'
[Plymouth Theme]
Name=BUXU OS
Description=Tela de boot do BUXU OS
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/buxu
ScriptFile=/usr/share/plymouth/themes/buxu/buxu.script
EOF

cat > config/includes.chroot/usr/share/plymouth/themes/buxu/buxu.script <<'EOF'
Window.SetBackgroundTopColor(1.0, 1.0, 1.0);
Window.SetBackgroundBottomColor(1.0, 1.0, 1.0);

pig.image = Image("porco.png");
pig.sprite = Sprite(pig.image);
pig.x = Window.GetX() + Window.GetWidth() / 2 - pig.image.GetWidth() / 2;
pig.y = Window.GetY() + Window.GetHeight() / 2 - pig.image.GetHeight() / 2 - 50;
pig.sprite.SetPosition(pig.x, pig.y, 10);

dot.image = Image("dot.png");
dot.count = 6;
dot.cx = Window.GetX() + Window.GetWidth() / 2;
dot.cy = pig.y + pig.image.GetHeight() + 70;
dot.radius = 20;
for (i = 0; i < dot.count; i++) {
    dot.sprite[i] = Sprite(dot.image);
    dot.sprite[i].SetZ(20);
    dot.sprite[i].SetOpacity(0);
}
global.frame = 0;

fun refresh_callback() {
    global.frame++;
    t = global.frame / 50.0;
    for (i = 0; i < dot.count; i++) {
        p = t * 0.45 - i * 0.055 + 20;
        p = p - Math.Int(p);
        e = p * p * (3 - 2 * p);
        angle = e * 2 * Math.Pi - Math.Pi / 2;
        x = dot.cx + dot.radius * Math.Cos(angle) - dot.image.GetWidth() / 2;
        y = dot.cy + dot.radius * Math.Sin(angle) - dot.image.GetHeight() / 2;
        dot.sprite[i].SetPosition(x, y, 20);
        dot.sprite[i].SetOpacity(1);
    }
}
Plymouth.SetRefreshFunction(refresh_callback);
EOF

# ---------- Barra de tarefas ----------
mkdir -p config/includes.chroot/etc/xdg/lxqt
mkdir -p config/includes.chroot/etc/skel/.config/lxqt
cat > config/includes.chroot/etc/xdg/lxqt/panel.conf <<'EOF'
[General]
__userfile__=true

[panel1]
alignment=-1
desktop=0
hidable=false
lockPanel=false
plugins=mainmenu, quicklaunch, taskbar, tray, statusnotifier, kbindicator, volume, worldclock, showdesktop
position=Bottom
reserve-space=true
width=100
width-percent=true

[mainmenu]
alignment=Left
type=mainmenu
ownIcon=true
icon=/usr/share/icons/buxu/porco.png
showText=false

[quicklaunch]
alignment=Left
apps\1\desktop=/usr/share/applications/pcmanfm-qt.desktop
apps\2\desktop=/usr/share/applications/qterminal.desktop
apps\3\desktop=/usr/share/applications/featherpad.desktop
apps\size=3
type=quicklaunch

[taskbar]
alignment=Left
type=taskbar

[tray]
alignment=Right
type=tray

[statusnotifier]
alignment=Right
type=statusnotifier

[kbindicator]
alignment=Right
type=kbindicator

[volume]
alignment=Right
type=volume

[worldclock]
alignment=Right
type=worldclock

[showdesktop]
alignment=Right
type=showdesktop
EOF
cp config/includes.chroot/etc/xdg/lxqt/panel.conf config/includes.chroot/etc/skel/.config/lxqt/panel.conf

# ---------- Swap de 8 GB (só no sistema instalado) ----------
mkdir -p config/includes.chroot/usr/local/sbin config/includes.chroot/etc/systemd/system
cat > config/includes.chroot/usr/local/sbin/buxu-swapfile <<'EOF'
#!/bin/bash
set -e
[ -e /swapfile ] && exit 0
livre=$(df --output=avail -BG / | tail -n1 | tr -dc '0-9')
tam=8
[ "${livre:-0}" -lt 20 ] && tam=4
fallocate -l "${tam}G" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=$((tam*1024))
chmod 600 /swapfile
mkswap /swapfile
grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw,pri=10 0 0' >> /etc/fstab
swapon -p 10 /swapfile || true
EOF
chmod +x config/includes.chroot/usr/local/sbin/buxu-swapfile
cat > config/includes.chroot/etc/systemd/system/buxu-swapfile.service <<'EOF'
[Unit]
Description=BUXU OS - cria o swap de 8 GB no sistema instalado
ConditionKernelCommandLine=!boot=live
ConditionPathExists=!/swapfile
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/buxu-swapfile

[Install]
WantedBy=multi-user.target
EOF

# ---------- Boot: entrar direto no modo live sem mostrar a tela amarela ----------
cat > config/hooks/normal/9000-buxu-boot.hook.binary <<'EOF'
#!/bin/sh
# Força boot automático instantâneo no Syslinux e no GRUB
B=binary
[ -d "$B" ] || B=.
for f in $(find "$B" -name '*.cfg' -o -name '*.cfg.in' 2>/dev/null); do
    sed -i -E 's/^([[:space:]]*)timeout[[:space:]]+[0-9]+/\1timeout 1/I' "$f" || true
    sed -i -E 's/^([[:space:]]*)set[[:space:]]+timeout=.*/\1set timeout=0/' "$f" || true
    sed -i -E 's/^([[:space:]]*)set[[:space:]]+timeout_style=.*/\1set timeout_style=hidden/' "$f" || true
done
exit 0
EOF
chmod +x config/hooks/normal/9000-buxu-boot.hook.binary

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

# LibreWolf
extrepo enable librewolf || true
apt-get update || true
apt-get install -y librewolf || echo "AVISO: LibreWolf não instalou"

# Flathub na loja
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || true

# Loja de programas com o nome BUXU Store
if [ -f /usr/share/applications/org.gnome.Software.desktop ]; then
    sed -i -E '/^Name(\[[^]]*\])?=/d' /usr/share/applications/org.gnome.Software.desktop
    sed -i '0,/^\[Desktop Entry\]/s//[Desktop Entry]\nName=BUXU Store\nName[pt_BR]=BUXU Store/' /usr/share/applications/org.gnome.Software.desktop
fi

# Ícone do porco no lugar do beija-flor (botão do menu)
if [ -f /usr/share/icons/buxu/porco.png ]; then
    PIG_B64=$(base64 -w0 /usr/share/icons/buxu/porco.png)
    find /usr/share/icons /usr/share/pixmaps -type f \( -name 'start-here-lxqt.*' -o -name 'start-here.*' \) 2>/dev/null | while read -r f; do
        case "$f" in
            *.svg) printf '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="256" height="256" viewBox="0 0 256 256"><image width="256" height="256" xlink:href="data:image/png;base64,%s"/></svg>' "$PIG_B64" > "$f" ;;
            *.png) cp /usr/share/icons/buxu/porco.png "$f" ;;
        esac
    done
    for d in /usr/share/icons/*/; do gtk-update-icon-cache -f "$d" >/dev/null 2>&1 || true; done
fi

# Instalador Calamares com a marca BUXU OS
if [ -d /etc/calamares ]; then
    for f in $(find /etc/calamares /usr/share/calamares -name 'branding.desc' 2>/dev/null); do
        sed -i -E '/^(productName|shortProductName|versionedName|shortVersionedName|bootloaderEntryName):/ s/Debian GNU\/Linux|Debian/BUXU OS/g' "$f" || true
    done
    for f in $(find /etc/calamares /usr/share/calamares -iname '*logo*.png' 2>/dev/null); do
        cp /usr/share/icons/buxu/porco.png "$f" || true
    done
    UC=/etc/calamares/modules/users.conf
    if [ -f "$UC" ]; then
        for k in doAutologin allowWeakPasswords allowWeakPasswordsDefault; do
            if grep -qE "^#?[[:space:]]*$k:" "$UC"; then
                sed -i -E "s/^#?[[:space:]]*$k:.*/$k: true/" "$UC"
            else
                echo "$k: true" >> "$UC"
            fi
        done
    fi
    RU=/etc/calamares/modules/removeuser.conf
    [ -f "$RU" ] && sed -i -E 's/^username:.*/username: buxu/' "$RU"
    for f in /usr/share/applications/*calamares*.desktop /usr/share/applications/*install-debian*.desktop; do
        [ -f "$f" ] && sed -i '0,/^\[Desktop Entry\]/s//[Desktop Entry]\nNoDisplay=true/' "$f"
    done
fi

systemctl enable buxu-live-setup.service || true
plymouth-set-default-theme -R buxu || true
systemctl enable buxu-swapfile.service || true
systemctl enable chrony || true
systemctl enable zramswap || true

apt-get clean
rm -rf /var/lib/apt/lists/*
EOF
chmod +x config/hooks/normal/0100-buxu.hook.chroot

# ---------- Configurações de Bootloader (boot rápido e oculto) ----------
mkdir -p config/bootloaders
if [ -d /usr/share/live/build/bootloaders ]; then
  cp -r /usr/share/live/build/bootloaders/. config/bootloaders/
fi
find config/bootloaders -type f \( -name '*.cfg' -o -name '*.cfg.in' \) | while read -r f; do
  sed -i -E 's/^([[:space:]]*)timeout[[:space:]]+[0-9]+/\1timeout 1/I' "$f" || true
  sed -i -E 's/^([[:space:]]*)set[[:space:]]+timeout=.*/\1set timeout=0/' "$f" || true
  sed -i -E 's/^([[:space:]]*)set[[:space:]]+timeout_style=.*/\1set timeout_style=hidden/' "$f" || true
done

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