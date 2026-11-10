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

# ---------- Login automático ----------
cat > config/includes.chroot/etc/lightdm/lightdm.conf.d/50-buxu.conf <<'EOF'
[Seat:*]
autologin-user=buxu
autologin-user-timeout=0
autologin-session=lxqt
EOF

# ---------- Imagens do porco (ícone do menu e tela de boot) ----------
mkdir -p config/includes.chroot/usr/share/icons/buxu
mkdir -p config/includes.chroot/usr/share/plymouth/themes/buxu

base64 -d > config/includes.chroot/usr/share/icons/buxu/porco.png <<'B64'
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
B64

base64 -d > config/includes.chroot/usr/share/plymouth/themes/buxu/porco.png <<'B64'
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
+P8DUqPQpaAqY/AAAAAASUVORK5CYII=
B64

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
# Sem 1 e 2 (áreas de trabalho) e sem o monitor azul à esquerda; sem o botão de desligar;
# botão "mostrar área de trabalho" (minimiza todas as janelas) ao lado do relógio.
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
plugins=fancymenu, quicklaunch, taskbar, tray, statusnotifier, kbindicator, volume, worldclock, showdesktop
position=Bottom
reserve-space=true
width=100
width-percent=true

[fancymenu]
alignment=Left
type=fancymenu
icon=/usr/share/icons/buxu/porco.png

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

# ---------- Swap de 8 GB (só no sistema instalado; no modo live seria na RAM) ----------
mkdir -p config/includes.chroot/usr/local/sbin config/includes.chroot/etc/systemd/system
cat > config/includes.chroot/usr/local/sbin/buxu-swapfile <<'EOF'
#!/bin/bash
# Cria um arquivo de swap de 8 GB (4 GB se o disco tiver pouco espaço livre)
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

# ---------- Boot: entrar direto no sistema, sem a tela de escolha de modo ----------
cat > config/hooks/normal/9000-buxu-boot.hook.binary <<'EOF'
#!/bin/sh
# Menu de boot invisível: espera ~0,1 s e entra no modo live
B=binary
[ -d "$B" ] || B=.
for f in $(find "$B" -path '*isolinux*' -name '*.cfg' 2>/dev/null); do
    sed -i -E 's/^([[:space:]]*)timeout[[:space:]]+[0-9]+/\1timeout 1/I' "$f" || true
done
for f in $(find "$B" -path '*grub*' -name '*.cfg' 2>/dev/null); do
    sed -i -E 's/^([[:space:]]*)set[[:space:]]+timeout=.*/\1set timeout=0/' "$f" || true
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

# LibreWolf (repositório oficial via extrepo)
extrepo enable librewolf
apt-get update
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

# Tela de boot do BUXU OS (porco + bolinhas)
plymouth-set-default-theme -R buxu || true

# Swap de 8 GB no sistema instalado
systemctl enable buxu-swapfile.service || true

# Relógio pela internet e zram ligados na inicialização
systemctl enable chrony || true
systemctl enable zramswap || true

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
