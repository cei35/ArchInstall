# ArchInstall

Minimal Arch Linux ISO with CLI-based installation and post-installation scripts, using `dialog` for a simple text-based UI.  
All installation scripts are written in Bash.

## Features

- **Language**: French by default  
- **Network configuration**: Wi-Fi / Ethernet (Static or DHCP)  
- **Disk setup**: Partitioning and LUKS encryption  

### Partition layout (Example for 64Go disk)
    
sda                     64G   disk
├─sda1                  512M  part   /boot       ef00
└─sda2                  63.5G part                8309
  └─vg_chif             63.5G crypt
    ├─vg_chif-lv_swap   2G     lvm    [SWAP]
    ├─vg_chif-lv_root   8G     lvm    /
    ├─vg_chif-lv_var    14G    lvm    /var
    ├─vg_chif-lv_usr    18G    lvm    /usr
    ├─vg_chif-lv_srv    2G     lvm    /srv
    └─vg_chif-lv_home   100%FREE lvm /home


- Base system installation  
- Post-installation steps  
- Package installation  
- Creation of `localadm` and `rescue` users  
- Sudo configuration  
- Installation of `yay` (AUR helper)  
- `/boot` mounted as `noauto` with pacman warnings (avoids accidental writes to `/boot`)  

## TODO

- Automate SSH setup  
- Integrate AppArmor and Firejail  
- Harden GRUB configuration
- Installation with GUI (possibly as a separate ISO)
- Maybe add MBR install
