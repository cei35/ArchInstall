# Custom Arch Linux ISO Build

Build a custom Arch Linux ISO with automated installation and post-installation scripts.

## Steps

1. **Install archiso** if not already installed:

```bash
sudo pacman -Sy archiso
```

2. **Copy the base releng configuration** to a custom iso folder:

```bash
cp -r /usr/share/archiso/configs/releng/ iso/
```

3. **Add dialog package to the base system**:

In packages.x86_64, add dialog:
```bash
dialog
```

4. **Copy scripts into the ISO**:

```bash
cp install.sh post_install.sh iso/airootfs/root/
```

5. **Modify .zlogin to execute scripts on first boot**:

iso/airootfs/root/.zlogin :

```bash
chmod +x ~/install.sh
~/install.sh
```

6. **Build the ISO**:

```bash
mkarchiso -v -w ~/work -o ~/out iso/
```

This process will generate a bootable ISO in ~/out with your custom scripts included.