#!/usr/bin/env bash

# Ignore Ctrl+C
trap '' SIGINT

DEBUG=0
[[ "$1" == "--debug" ]] && DEBUG=1

run_step() {
    local msg="$1"
    shift
    if (( DEBUG )); then
        echo "==> $msg"
        "$@"
    else
        dialog --title "ArchInstall" --infobox "$msg..." 8 60
        "$@" &>/dev/null
    fi
}

# Verify dialog
if ! command -v dialog &>/dev/null; then
    echo "dialog not found, please install it first."
    exit 1
fi

dialog --title "ArchInstall" --yesno "You have chosen UEFI Install.\nDo you want to continue ?" 8 60
[[ $? -ne 0 ]] && exit 0

# Set keyboard to French
loadkeys fr

# Check internet connectivity
dialog --title "ArchInstall" --infobox "Checking network connectivity..." 8 60
if ! ping -c 3 archlinux.org &>/dev/null; then

    # Network configuration
    choice=$(dialog --stdout --title "Network configuration" --menu "Choose network setup:" 15 60 3 \
        1 "Ethernet (DHCP)" \
        2 "Wi-Fi (iwd)" \
        3 "Static IP")

    interfaces=($(ls /sys/class/net | grep -v lo))
    choices=""
    for i in "${interfaces[@]}"; do
        choices+="$i $i "
    done

    iface=$(dialog --stdout --title "Select interface" --menu "Choose network interface:" 15 60 5 $choices)
    [ -z "$iface" ] && exit 1

    case $choice in
    1)
        cat > /etc/systemd/network/$iface.network <<EOF
[Match]
Name=$iface

[Network]
DHCP=yes
EOF

    systemctl enable --now systemd-networkd
        ;;

    2)
        systemctl enable --now iwd

            cat > /etc/systemd/network/$iface.network <<EOF
[Match]
Name=$iface

[Network]
DHCP=yes
EOF

        iwctl station "$iface" scan
        networks=$(iwctl station "$iface" get-networks | awk 'NR>4 {print $2 " " $2}' | sed '/^$/d')

        ssid=$(dialog --stdout --title "Wi-Fi" --menu "Select SSID:" 20 60 10 $networks)
        [ -z "$ssid" ] && exit 1

        wifi_pass=$(dialog --stdout --title "Wi-Fi Password" --insecure --passwordbox "Enter password for $ssid:" 8 60)
        [ -z "$wifi_pass" ] && exit 1

        iwctl --passphrase "$wifi_pass" station "$iface" connect "$ssid"
        ;;

    3)
        ip_addr=$(dialog --stdout --inputbox "Enter static IP (ex: 192.168.1.50/24):" 8 60)
        gateway=$(dialog --stdout --inputbox "Enter Gateway IP:" 8 60)

        cat > /etc/systemd/network/$iface.network <<EOF
[Match]
Name=$iface

[Network]
Address=$ip_addr
Gateway=$gateway
EOF

    systemctl enable --now systemd-networkd
        ;;
    esac
    
    # Test network connectivity
    for i in {1..10}; do # wait up to 10 seconds for an IP address
        ip addr show "$iface" | grep -q "inet " && break
        sleep 1
    done

    dialog --title "ArchInstall" --infobox "Testing network connectivity..." 8 60
    if ! ping -c 3 archlinux.org &>/dev/null; then
        dialog --title "ArchInstall" --msgbox "Network connectivity test failed. Please check your network settings.\nAfter fixing the issue, restart the installation with ./install.sh" 8 60
        exit 1
    fi
fi

# disk overview
lsblk > /tmp/lsblk
dialog --title "ArchInstall - Disks overview" --textbox /tmp/lsblk 20 80

# disk menu
disks=()
while read -r line; do
    name=$(echo $line | awk '{print $1}')
    type=$(echo $line | awk '{print $2}')
    size=$(echo $line | awk '{print $3}')
    [[ $type == "disk" ]] && disks+=("$name" "$size")
done < <(lsblk -d -o NAME,TYPE,SIZE | tail -n +2)

disk=$(dialog --title "ArchInstall - Select disk" --menu "Choose a disk:" 15 50 5 "${disks[@]}" 3>&1 1>&2 2>&3)
[[ ! -b "/dev/$disk" ]] && dialog --msgbox "Disk /dev/$disk does not exist!" 8 60 && exit 1

# umount all
dialog --infobox "Cleaning mounts on /dev/$disk..." 8 60

vgchange -an vg_chif 2>/dev/null
cryptsetup close lvm_chif 2>/dev/null

mountpoints=$(lsblk -nrpo MOUNTPOINT /dev/$disk | grep -v '^$' | sort -u)
for mp in $mountpoints; do
    umount -R "$mp" 2>/dev/null
done

# Partitioning
run_step "Partitioning $disk" sgdisk -o \
  -n 1:0:+512M -t 1:ef00 \
  -n 2:0:0 -t 2:8309 \
  /dev/$disk

partprobe /dev/$disk
part1="/dev/$(lsblk -lno NAME,TYPE /dev/$disk | awk '$2=="part"{print $1}' | sed -n '1p')"
part2="/dev/$(lsblk -lno NAME,TYPE /dev/$disk | awk '$2=="part"{print $1}' | sed -n '2p')"

run_step "Formatting partitions" mkfs.fat -F 32 $part1
run_step "Formatting partitions" mkfs.ext4 $part2

# LUKS

while :; do
    passphrase=$(dialog --title "ArchInstall - LUKS" --insecure --passwordbox "Enter LUKS passphrase:" 8 60 3>&1 1>&2 2>&3) || exit 1
    passphrase_v2=$(dialog --title "ArchInstall - LUKS" --insecure --passwordbox "Confirm LUKS passphrase:" 8 60 3>&1 1>&2 2>&3) || exit 1

    [[ "$passphrase" == "$passphrase_v2" ]] && break
    dialog --title "ArchInstall - LUKS passphrase mismatch" --msgbox "Passphrases do not match. Please try again." 8 60
done

dialog --infobox "Encrypting $part2. This could take a while..." 8 60

if (( DEBUG )); then
    echo -n "$passphrase" | cryptsetup luksFormat $part2 -
    echo -n "$passphrase" | cryptsetup open $part2 lvm_chif -
else
    echo -n "$passphrase" | cryptsetup luksFormat $part2 - &>/dev/null
    echo -n "$passphrase" | cryptsetup open $part2 lvm_chif - &>/dev/null
fi

# LVM
run_step "Setting up LVM" pvcreate /dev/mapper/lvm_chif
run_step "Setting up LVM" vgcreate vg_chif /dev/mapper/lvm_chif

disk_size_gb=$(( $(lsblk -dbno SIZE /dev/$disk) / 1024 / 1024 / 1024 ))
export disk_size_gb
run_step "Creating logical volumes" bash -c '
if (( disk_size_gb <= 128 )); then # 64 Go
    swap="2G";root="8G";var="14G";usr="18G";srv="2G"

elif (( disk_size_gb <= 300 )); then # 256 Go
    swap="8G";root="20G";var="30G";usr="50G";srv="5G"

elif (( disk_size_gb <= 600 )); then # 512 Go
    swap="8G";root="50G";var="75G";usr="50G";srv="10G"

else # 1 To
    swap="16G";root="128G";var="150G";usr="128G";srv="32G"
fi

lvcreate -L $swap -n lv_swap vg_chif
lvcreate -L $root -n lv_root vg_chif
lvcreate -L $var -n lv_var vg_chif
lvcreate -L $usr -n lv_usr vg_chif
lvcreate -L $srv -n lv_srv vg_chif
lvcreate -l 100%FREE -n lv_home vg_chif
'

run_step "Formatting LVs" bash -c '
mkfs.ext4 /dev/vg_chif/lv_root
mkfs.ext4 /dev/vg_chif/lv_var
mkfs.ext4 /dev/vg_chif/lv_usr
mkfs.ext4 /dev/vg_chif/lv_srv
mkfs.ext4 /dev/vg_chif/lv_home
mkswap /dev/vg_chif/lv_swap
'

# Mount filesystems (Home is mounted without noexec to allow user scripts)
export part1
run_step "Mounting filesystems" bash -c "
echo 'Mounting files system'
mount /dev/vg_chif/lv_root /mnt
mount --mkdir $part1 /mnt/boot -o nosuid,nodev,noexec
mount --mkdir /dev/vg_chif/lv_var /mnt/var -o nosuid,nodev,noexec
mount --mkdir /dev/vg_chif/lv_usr /mnt/usr -o nodev
mount --mkdir /dev/vg_chif/lv_srv /mnt/srv -o nosuid,nodev,noexec
mount --mkdir /dev/vg_chif/lv_home /mnt/home -o nosuid,nodev
swapon /dev/vg_chif/lv_swap
"

lsblk > /tmp/lsblk
dialog --title "ArchInstall - Partitioning" --textbox /tmp/lsblk 20 80
dialog --title "ArchInstall - Confirm partitioning" --yesno "Configuration OK?" 8 60 || exit 0

hostname=$(dialog --title "ArchInstall - Hostname" --inputbox "Enter hostname:" 8 60 3>&1 1>&2 2>&3)

while :; do
    password=$(dialog --title "ArchInstall - Root password" --insecure --passwordbox "Enter root password:" 8 60 3>&1 1>&2 2>&3) || exit 1
    password_v2=$(dialog --title "ArchInstall - Root password" --insecure --passwordbox "Confirm root password:" 8 60 3>&1 1>&2 2>&3) || exit 1

    [[ "$password" == "$password_v2" ]] && break
    dialog --title "ArchInstall - root password mismatch" --msgbox "Passwords do not match. Please try again." 8 60
done

# Install base system
run_step "Updating GPG keys" pacman-key --init
run_step "Populating keys" pacman-key --populate archlinux
run_step "Installing base system" pacstrap -K /mnt base base-devel linux linux-firmware vim iwd wpa_supplicant dialog
run_step "Generating fstab" bash -c "genfstab -U /mnt >> /mnt/etc/fstab"

# Chroot config
run_step "Entering chroot" arch-chroot /mnt /bin/bash -e <<EOF
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
mv /etc/locale.gen /etc/locale.gen.old
echo "fr_FR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
echo "KEYMAP=fr" > /etc/vconsole.conf
hwclock --systohc
echo "$hostname" > /etc/hostname
pacman -Sy lvm2 --noconfirm
sed -i '/^HOOKS=/ s/filesystems/filesystems encrypt lvm2 usr/' /etc/mkinitcpio.conf
mkinitcpio -P
echo "root:$password" | chpasswd

pacman -Sy grub efibootmgr --noconfirm
sed -i 's/^#\s*GRUB_ENABLE_CRYPTODISK=y/GRUB_ENABLE_CRYPTODISK=y/' /etc/default/grub
sed -i '8i\GRUB_CMDLINE_LINUX="cryptdevice=UUID='$(blkid -s UUID -o value ${part2})':vg_chif root=/dev/mapper/vg_chif-lv_root"' /etc/default/grub
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg
EOF

if (( $DEBUG )); then
    echo "locale.gen: $(cat /mnt/etc/locale.gen)
    locale.conf: $(cat /mnt/etc/locale.conf)
    vconsole.conf: $(cat /mnt/etc/vconsole.conf)
    hostname: $(cat /mnt/etc/hostname)
    fstab: $(cat /mnt/etc/fstab)
    HOOKS in mkinitcpio.conf: $(cat /mnt/etc/mkinitcpio.conf | grep HOOKS)
    grub cmdline: $(cat /mnt/etc/default/grub | grep GRUB_CMDLINE_LINUX)" > /tmp/chroot_config

    dialog --title "ArchInstall - Chroot configuration" --textbox /tmp/chroot_config 20 80
    dialog --title "ArchInstall - Confirm chroot" --yesno "Configuration OK?" 8 60 || exit 0
fi

# Post-install script
dialog --title "ArchInstall" --infobox "Setting up post-install script..." 8 60
cp /root/post_install.sh /mnt/root/
chmod +x /mnt/root/post_install.sh

cat <<'EOF' >> /mnt/root/.bash_profile
# This can be deleted after first boot
if [ -f /root/post_install.sh ]; then
    /root/post_install.sh
    rm -f /root/post_install.sh
fi
EOF

run_step "Unmounting partitions" bash -c "umount -R /mnt; swapoff -a"

disks=$(lsblk -dpno NAME,TYPE,SIZE | awk '$2 ~ /(disk|rom)/ {print $1, $3}')
device=$(dialog --stdout --menu "Choisissez le périphérique à éjecter :" 20 60 10 $disks)
[ -n "$device" ] && eject "$device"


if dialog --title "ArchInstall" --yesno "Installation complete. Reboot now ?\n\nPost-install script will be executed." 8 60; then
    reboot
fi