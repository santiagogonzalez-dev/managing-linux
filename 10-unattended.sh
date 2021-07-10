#!/usr/bin/env bash

clear   # Clear the TTY
set -e  # The script will not run if we CTRL + C, or in case of an error
set -u  # Treat unset variables as an error when substituting

# I commented everything for some reason
# Default settings
# /dev/nvme0n1 is the drive
# /dev/nvme0n1p1 is boot
# /dev/nvme0n1p2 is root
continent_city=America/Argentina/Mendoza
hostname=bebop
username=st
keymap=dvorak
read -s -p "Enter userpass: " user_password
read -s -p "Enter rootpass: " root_password
echo -e "\n"

timedatectl set-ntp true  # Synchronize motherboard clock
sgdisk --zap-all /dev/nvme0n1  # Delete tables
printf "n\n1\n\n+333M\nef00\nn\n2\n\n\n\nw\ny\n" | gdisk /dev/nvme0n1  # Format the drive

mkdir -p -m0700 /run/cryptsetup  # Change permission to root only
cryptsetup luksFormat --type luks2 /dev/nvme0n1p2  # Encrypt the drive with luks2
cryptsetup luksOpen /dev/nvme0n1p2 cryptroot  # Open the mapper

mkfs.vfat -F32 /dev/nvme0n1p1  # Format the EFI partition
mkfs.btrfs /dev/mapper/cryptroot  # Format the mapper
# Mount to create the subvolumes
mount /dev/mapper/cryptroot /mnt
btrfs su cr /mnt/@
btrfs su cr /mnt/@home
btrfs su cr /mnt/@pkg
btrfs su cr /mnt/@srv
btrfs su cr /mnt/@log
btrfs su cr /mnt/@tmp
btrfs su cr /mnt/@btrfs
umount /mnt
# Unmount so that now we can mount the subvolumes
mount -o noatime,nodiratime,compress-force=zstd:1,discard=async,space_cache=v2,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,var/cache/pacman/pkg,srv,log,tmp,btrfs,boot}  # Create directories for their respective subvolumes
mount -o noatime,nodiratime,compress-force=zstd:1,discard=async,space_cache=v2,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,nodiratime,compress-force=zstd:1,discard=async,space_cache=v2,subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o noatime,nodiratime,compress-force=zstd:1,discard=async,space_cache=v2,subvol=@srv /dev/mapper/cryptroot /mnt/srv
mount -o noatime,nodiratime,compress-force=zstd:1,discard=async,space_cache=v2,subvol=@log /dev/mapper/cryptroot /mnt/log
mount -o noatime,nodiratime,compress-force=zstd:1,discard=async,space_cache=v2,subvol=@tmp /dev/mapper/cryptroot /mnt/tmp
mount -o noatime,nodiratime,compress=zstd,space_cache,subvolid=5 /dev/mapper/cryptroot /mnt/btrfs
mount /dev/nvme0n1p1 /mnt/boot  # Mount the boot partition

sed -i "/#Color/a ILoveCandy" /etc/pacman.conf  # Making pacman prettier
sed -i "s/#Color/Color/g" /etc/pacman.conf  # Add color to pacman
sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 8/g" /etc/pacman.conf  # Parallel downloads

pacstrap /mnt base base-devel linux linux-firmware \  # Basic packages
    intel-ucode \  # I only have Intel machines at the moment
    networkmanager \  # NetworkManager for internet access
    efibootmgr \  # To manage boot entries I use this
    btrfs-progs \ # btrfs-progs is needed if you use BTRFS
    wget git rsync \ # I pull my second script with this
    neovim \  # Default editor
    zsh \  # Default shell for the default user

genfstab -U /mnt >> /mnt/etc/fstab  # Generate the entries for fstab
#arch-chroot /mnt /bin/bash << EOF
timedatectl set-ntp true  # Synchronize 
ln -sf /usr/share/zoneinfo/$continent_city /etc/localtime  # Configure locale
hwclock --systohc  # Synchronize the clock
sed -i "s/#en_US/en_US/g; s/#es_AR/es_AR/g" /etc/locale.gen  # Add locales
echo "LANG=en_US.UTF-8" > /etc/locale.conf  # Default lang locale
locale-gen  # Generate locale

echo -e "127.0.0.1\tlocalhost" >> /etc/hosts  # The next three lines will configure the localhost
echo -e "::1\t\tlocalhost" >> /etc/hosts  # And the name other computers will see you with as well
echo -e "127.0.1.1\t$hostname.localdomain\t$hostname" >> /etc/hosts

echo -e "KEYMAP=$keymap" > /etc/vconsole.conf  # Default keymap in TTY
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers  # Add the wheel group
echo "Defaults !tty_tickets" >> /etc/sudoers  # You don't need to put your password again on another terminal
# These two next lines are configs for pacman
sed -i "/#Color/a ILoveCandy" /etc/pacman.conf  
sed -i "s/#Color/Color/g; s/#ParallelDownloads = 5/ParallelDownloads = 6/g; s/#UseSyslog/UseSyslog/g; s/#VerbosePkgLists/VerbosePkgLists/g" /etc/pacman.conf
# Use all threads of your CPU and utilize multiple cores on compression
sed -i 's/#MAKEFLAGS="-j2"/MAKEFLAGS="-j$(nproc)"/g; s/-)/--threads=0 -)/g; s/gzip/pigz/g; s/bzip2/pbzip2/g' /etc/makepkg.conf

# This is the name of your computer and is the same that is being used for localhost config
echo $hostname > /etc/hostname  
# Add multiple groups  and change the shell for the default user
useradd -m -g users -G wheel,games,power,optical,storage,scanner,lp,audio,video,input,adm,users -s /bin/zsh $username  
echo -en "$root_password\n$root_password" | passwd  # Configure password for root
echo -en "$user_password\n$user_password" | passwd $username  # Configure password for the default user

git clone https://github.com/santigo-zero/Dotfiles.git
rsync --recursive --verbose --exclude '.git' --exclude 'README.md' Dotfiles/ /home/$username
rm -rf Dotfiles

# Add some folders for the default user and download the 20-script that will install KDE Plasma, fonts, AUR manager and other packages
mkdir /usr/share/backgrounds  # Add a backgrounds folder for wallpapers and icons
chmod 750 /usr/share/backgrounds
chown $username /usr/share/backgrounds

mkdir /home/$username/kdeconnect  # To transfer things with kdeconnect
chmod 750 /home/$username/kdeconnect
chown $username /home/$username/kdeconnect

mkdir /home/$username/workspace  # This is where everything goes, repos, scripts, exercises
chmod 750 /home/$username/workspace
chown $username /home/$username/workspace

wget https://raw.githubusercontent.com/santigo-zero/csjarchlinux/master/20-packages.sh -P /home/$username
chmod +x /home/$username/20-packages.sh
chmod 750 /home/$username/20-packages.sh
chown $username /home/$username/20-packages.sh

systemctl enable NetworkManager.service  # Enable NetworkManager

journalctl --vacuum-size=100M  # Just make the journal smaller
journalctl --vacuum-time=2weeks  # And clean it every two weaks

touch /etc/sysctl.d/99-swappiness.conf
echo 'vm.swappiness=20' > /etc/sysctl.d/99-swappiness.conf  # Lowers the value so that the kernel avoids swapping too much

mkdir -p /etc/pacman.d/hooks/
touch /etc/pacman.d/hooks/100-systemd-boot.hook  # This hook updates automatically the EFI boot manager
tee -a /etc/pacman.d/hooks/100-systemd-boot.hook << END
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Updating systemd-boot
When = PostTransaction
Exec = /usr/bin/bootctl update
END

sed -i "s/^HOOKS.*/HOOKS=(base systemd keyboard autodetect sd-vconsole modconf block sd-encrypt btrfs filesystems fsck)/g" /etc/mkinitcpio.conf
sed -i 's/^MODULES.*/MODULES=(intel_agp i915)/' /etc/mkinitcpio.conf  # Configure systemd, btrfs module, encryption, keymap and graphics hooks
mkinitcpio -P  # Regenarte images
bootctl --path=/boot/ install  # Install systemd-boot

mkdir -p /boot/loader/  # Bootloader configuration
tee -a /boot/loader/loader.conf << END
default arch.conf
console-mode max
editor no
END
# The rest of this script just creates the files to manage Linux, Linux Zen and Linux LTS, you don't need to install all kernels
mkdir -p /boot/loader/entries/
touch /boot/loader/entries/arch.conf
tee -a /boot/loader/entries/arch.conf << END
title Arch Linux
linux /vmlinuz-linux
initrd /intel-ucode.img
initrd /initramfs-linux.img
options rd.luks.name=$(blkid -s UUID -o value /dev/nvme0n1p2)=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rd.luks.options=discard i915.fastboot=1 i915.enable_fbc=1 i915.enable_guc=2 nmi_watchdog=0 quiet rw
END

touch /boot/loader/entries/arch-zen.conf
tee -a /boot/loader/entries/arch-zen.conf << END
title Arch Linux Zen
linux /vmlinuz-linux-zen
initrd /intel-ucode.img
initrd /initramfs-linux-zen.img
options rd.luks.name=$(blkid -s UUID -o value /dev/nvme0n1p2)=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rd.luks.options=discard i915.fastboot=1 i915.enable_fbc=1 i915.enable_guc=2 nmi_watchdog=0 quiet rw
END

touch /boot/loader/entries/arch-lts.conf
tee -a /boot/loader/entries/arch-lts.conf << END
title Arch Linux LTS
linux /vmlinuz-linux-lts
initrd /intel-ucode.img
initrd /initramfs-linux-lts.img
options rd.luks.name=$(blkid -s UUID -o value /dev/nvme0n1p2)=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rd.luks.options=discard i915.fastboot=1 i915.enable_fbc=1 i915.enable_guc=2 nmi_watchdog=0 quiet rw
END
EOF
umount -R /mnt