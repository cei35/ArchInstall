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

echo "[+] Building ArchInstall ISO..."

echo "[+] Installing archiso package if needed..."
sudo pacman -Sy --noconfirm --needed archiso

echo "[+] Setting up build environment..."
mkdir -p build
cd build

echo "[+] Copying releng profile..."
rm -rf iso/
cp -r /usr/share/archiso/configs/releng/ iso/

echo "[+] Adding dialog packages..."

# Add dialog to packages
grep -qF "dialog" iso/packages.x86_64 || {
    echo "dialog" >> iso/packages.x86_64
    sort -o iso/packages.x86_64 iso/packages.x86_64
}

echo "[+] Select type :
1. UEFI Core Only
2. UEFI GUI (only Xfce4, Hyprland or Gnome for now)
"

read -n 1 -rp "[?] Choose number : " choice

case $choice in
1)
    echo "[+] Setting up UEFI Core Only ISO..."
    cp ../scripts/core/core_install_uefi.sh iso/airootfs/scripts/install.sh
    cp ../scripts/core/core_post_install_uefi.sh iso/airootfs/scripts/post_install.sh
    mode="core"
    ;;
2)
    echo "[+] Setting up UEFI GUI ISO..."
    cp ../scripts/gui/gui_install_uefi.sh iso/airootfs/scripts/install.sh
    cp ../scripts/gui/gui_post_install_uefi.sh iso/airootfs/scripts/post_install.sh
    mode="gui"
    ;;
*)
    echo "[-] Invalid choice. Exiting."
    exit 1
    ;;
esac

echo "[+] Building ISO..."
mkdir -p work out
mkarchiso -v -w work -o out iso

ISO="archinstall_${mode}_$(date +%Y-%m-%d).iso"
mv out/*.iso "$ISO"

echo "[+] build complete: $ISO"