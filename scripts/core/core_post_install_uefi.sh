#!/usr/bin/env bash

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 
    exit
fi

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

# Check internet connectivity
dialog --title "Network Configuration" --infobox "Checking network connectivity..." 8 60
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

    t=10
    while ! systemctl is-active --quiet iwd; do
        ((t--))
        if ((t == 0)); then
            dialog --title "Network Configuration - Error" --msgbox "Error: iwd service failed to start." 8 60
            cp /root/post_install.sh /root/post_install.sh.bak
            exit 1
        fi
        sleep 0.5
    done

        cat > /etc/systemd/network/$iface.network <<EOF
[Match]
Name=$iface

[Network]
DHCP=ipv4
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

cp /etc/resolv.conf{,.bak}
cp /etc/systemd/timesyncd.conf{,.bak}

run_step "Setting up DNS and NTP" /bin/bash -e <<EOF
echo "DNS=8.8.8.8
FallbackDNS=1.1.1.1
DNSSEC=yes
DNSOverTls=opportunistic
LLMNR=no" > /etc/systemd/resolved.conf
systemctl enable --now systemd-resolved

echo "NTP=fr.pool.ntp.org" >> /etc/systemd/timesyncd.conf
systemctl enable --now systemd-timesyncd
EOF

# Test network connectivity
dialog --title "ArchInstall" --infobox "Testing network connectivity..." 8 60
for i in {1..10}; do # wait up to 10 seconds for an IP address
    ip addr show "$iface" | grep -q "inet " && break
    sleep 1
done

dialog --title "ArchInstall" --infobox "Testing network connectivity..." 8 60
if ! ping -c 3 archlinux.org &>/dev/null; then
    cp /root/post_install.sh /root/post_install.sh.bak
    dialog --title "ArchInstall" --msgbox "Network connectivity test failed. Please check your network settings.\nAfter fixing the issue, restart the installation with ./install.sh" 8 60
    exit 1
fi

run_step "pseudo filesystems" /bin/bash -e <<EOF
echo "proc /proc proc defaults,hidepid=2 0 0
tmpfs /tmp tmpfs defaults,nosuid,nodev,noexec 0 0
tmpfs /var/log tmpfs nosuid,nodev,noexec 0 0" >> /etc/fstab

sed -i '/\/boot/ s/noexec/noexec,noauto/' /etc/fstab
EOF

run_step "Installing packages" /bin/bash -e <<EOF
chmod -R 700 /etc/iptables

pacman -Syu --needed --noconfirm make base-devel git cron wget lynx nnn python3 python-pip go sudo openssh
useradd -m -U -s /bin/bash localadm
useradd -m -U -s /bin/bash rescue
EOF

#localadm password
while :; do
    password=$(dialog --title "Set localadm password" --insecure --passwordbox "Enter password for localadm:" 8 60 3>&1 1>&2 2>&3) || exit 1
    password_v2=$(dialog --title "Confirm localadm password" --insecure --passwordbox "Confirm password for localadm:" 8 60 3>&1 1>&2 2>&3) || exit 1

    [[ "$password" == "$password_v2" ]] && break
    dialog --title "ArchInstall - localadm password mismatch" --msgbox "Passwords do not match. Please try again." 8 60
done
echo "localadm:$password" | chpasswd

#rescue password
while :; do
    password=$(dialog --title "Set rescue password" --insecure --passwordbox "Enter password for rescue:" 8 60 3>&1 1>&2 2>&3) || exit 1
    password_v2=$(dialog --title "Confirm rescue password" --insecure --passwordbox "Enter password for rescue:" 8 60 3>&1 1>&2 2>&3) || exit 1

    [[ "$password" == "$password_v2" ]] && break
    dialog --title "ArchInstall - rescue password mismatch" --msgbox "Passwords do not match. Please try again." 8 60
done
echo "rescue:$password" | chpasswd

# Create main user without sudo rights
name=$(dialog --title "Main user" --inputbox "Enter main username:" 8 60 3>&1 1>&2 2>&3)
[ -z "$name" ] && exit 1

useradd -m -U -s /bin/bash "$name"

while :; do
    pass=$(dialog --title "Set $name password" --insecure --passwordbox "Enter password for $name:" 8 60 3>&1 1>&2 2>&3) || exit 1
    pass_v2=$(dialog --title "Confirm $name password" --insecure --passwordbox "Enter password for $name:" 8 60 3>&1 1>&2 2>&3) || exit 1

    [[ "$pass" == "$pass_v2" ]] && break
    dialog --title "ArchInstall - $name password mismatch" --msgbox "Passwords do not match. Please try again." 8 60
done
echo "$name:$pass" | chpasswd

run_step "Configuring sudoers" /bin/bash -c '
echo "localadm ALL=(ALL:ALL) NOPASSWD:ALL" >> /etc/sudoers
echo "rescue ALL=(ALL:ALL) ALL" >> /etc/sudoers

ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
passwd -l root

cat <<'"'"'EOF'"'"' > /usr/local/bin/pacman
#!/bin/bash

if ! findmnt -n /boot &>/dev/null; then
    echo "Error : /boot is not mounted !"
    exit 1
fi

exec /usr/bin/pacman "$@"
EOF

chmod +x /usr/local/bin/pacman
'
# Setup localadm
run_step "Setup localadm" su - localadm -s /bin/bash -c '
cd ~
echo "alias ll=\"ls -lahF\"" >> ~/.bashrc
echo "PS1='\''\${debian_chroot:+(\$debian_chroot)}\[\033[01;33m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '\''" >> ~/.bashrc

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg --syncdeps --install --needed --noconfirm --clean
'
# Setup $name
run_step "Setup $name" su - "$name" -s /bin/bash -c '
cd ~
echo "alias ll=\"ls -lahF\"" >> ~/.bashrc
echo "PS1='\''\${debian_chroot:+(\$debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '\''" >> ~/.bashrc
'

# prolly nothing to update but just in case
run_step "Update system" yay -Syu

dialog --title "ArchInstall - Post-install" --yesno "Installation complete. Reboot now ?" 8 60
[[ $? -ne 0 ]] && exit 0

reboot