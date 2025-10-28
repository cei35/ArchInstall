#!/bin/bash

# This script builds the ISO image for ArchInstall
# Usage: ./build_iso.sh
#
# possibilities :
# UEFI
#   - Core 
#   - GUI
#
#
# TODO:
# Add MBR install AND Server version (with SSH/Auditd...)

set -e

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

echo "[+] Building ArchInstall ISO..."

echo "[+] Installing archiso package if needed..."
sudo pacman -Sy --noconfirm --needed archiso

echo ""
echo "[+] Setting up build environment..."
mkdir -p build
cd build

echo "[+] Copying releng profile..."
rm -rf iso/ out/ work/
cp -r /usr/share/archiso/configs/releng/ iso/

echo "[+] Adding dialog packages..."

# Add dialog to packages
grep -qF "dialog" iso/packages.x86_64 || {
    echo "dialog" >> iso/packages.x86_64
    sort -o iso/packages.x86_64 iso/packages.x86_64
}

echo ""
echo "[+] Select ISO type to build:
1. UEFI Core Only
2. UEFI GUI (only Xfce4, Hyprland or Gnome for now)
"

read -n 1 -rp "[?] Choose number : " choice

cp ../scripts/core/core_install_uefi.sh iso/airootfs/root/install.sh

case $choice in
1)
    echo "[+] Setting up UEFI Core Only ISO..."
    cp ../scripts/core/core_post_install_uefi.sh iso/airootfs/root/post_install.sh
    mode="core"
    ;;
2)
    echo "[+] Setting up UEFI GUI ISO..."
    cp ../scripts/gui/gui_post_install_uefi.sh iso/airootfs/root/post_install.sh
    mode="gui"
    ;;
*)
    echo "[-] Invalid choice. Exiting."
    exit 1
    ;;
esac

chmod +x iso/airootfs/root/*.sh

echo "
chmod +x ~/install.sh
~/install.sh" >> iso/airootfs/root/.zlogin

echo "[+] Building ISO..."
mkdir -p work out

t0=$(date +%s)
mkarchiso -v -w work -o out iso
t1=$(date +%s)

ISO="archinstall_${mode}_$(date +%Y-%m-%d).iso"
mv out/*.iso "$ISO"

echo "[+] build complete: $ISO (in $((t1 - t0)) seconds)"