#!/usr/bin/env bash

# TODO(santigo-zero): Fix configuration of makepkg, sed commands are not correct

clear # Clear the TTY
set -e # The script will stop running if we CTRL + C, or in case of an error
set -u # Treat unset variables as an error when substituting

# DESCRIPTION: This script is a little bit more simple, it wipes the selected drive and it's
# not interactive at all

# TODO(everyone): Change the variables below to fit your needs. If your
# drive is at /dev/sda, it's going to be wiped and formated to have /dev/sda1
# and /dev/sda2 as boot and root partitions respectively, the defaults are
# for a conventional NVMe. Also make sure to fill all the variables since if you
# don't it will result on the script failing.

keymap=""
username=""
hostname=""
user_password=""
root_password=""

drive_password="" # Encryption key
drive=/dev/nvme0n1 # Drive we are going to format
part_boot=/dev/nvme0n1p1  # Boot partition
part_root=/dev/nvme0n1p2  # Root partition
cpu_model="intel-ucode"
# cpu_model="amd-ucode"

# Delete tables/partitions on the selected drive
sgdisk --zap-all "${drive}"

# Format the drive, createing a first partition of 800M and the second one that
# takes the rest of the drive
printf "n\n1\n\n+800M\nef00\nn\n2\n\n\n\nw\ny\n" | gdisk "${drive}"

# Encrypt drive and open encrypted mapper
echo -n "$drive_password" | cryptsetup luksFormat --type luks2 "${part_root}" -d -
echo -n "$drive_password" | cryptsetup open "${part_root}" cryptroot -d -

# Format boot and root partitions
mkfs.vfat -F32 "${part_boot}"
mkfs.btrfs /dev/mapper/cryptroot

# Create btrfs subvolumes
mount /dev/mapper/cryptroot /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@pkg
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@srv
btrfs subvolume create /mnt/@tmp
umount /mnt

# Mount the subvolumes
mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@ /dev/mapper/cryptroot /mnt
mkdir -p /mnt/{home,var/cache/pacman/pkg,var,srv,tmp,boot}  # Create directories for each subvolume
mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@home /dev/mapper/cryptroot /mnt/home
mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@pkg /dev/mapper/cryptroot /mnt/var/cache/pacman/pkg
mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@var /dev/mapper/cryptroot /mnt/var
mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@srv /dev/mapper/cryptroot /mnt/srv
mount -o noatime,compress-force=zstd:1,space_cache=v2,subvol=@tmp /dev/mapper/cryptroot /mnt/tmp
chattr +C /mnt/var  # Copy on write disabled for /var
mount "${part_boot}" /mnt/boot  # Mount the boot partition

# Configure pacman
sed -i "/#Color/a ILoveCandy" /etc/pacman.conf  # Making pacman prettier
sed -i "s/#Color/Color/g" /etc/pacman.conf  # Add color to pacman
sed -i "s/#ParallelDownloads = 5/ParallelDownloads = 5/g" /etc/pacman.conf  # Parallel downloads

# Pacstrap
pacstrap /mnt base base-devel linux linux-firmware networkmanager efibootmgr "$cpu_model" btrfs-progs

# Generate the entries for fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot
arch-chroot /mnt /bin/bash << EOF
ln -sf /usr/share/zoneinfo/"$(curl -s http://ip-api.com/line?fields=timezone)" /etc/localtime &>/dev/null
hwclock --systohc
sed -i "s/#en_US/en_US/g; s/#es_AR/es_AR/g" /etc/locale.gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
locale-gen

echo -e "127.0.0.1\tlocalhost" > /etc/hosts
echo -e "::1\t\tlocalhost" >> /etc/hosts
echo -e "127.0.1.1\t$hostname.localdomain\t$hostname" >> /etc/hosts

echo -e "KEYMAP=$keymap" > /etc/vconsole.conf
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
echo "Defaults !tty_tickets" >> /etc/sudoers
sed -i "/#Color/a ILoveCandy" /etc/pacman.conf
sed -i "s/#Color/Color/g; s/#ParallelDownloads = 5/ParallelDownloads = 6/g; s/#UseSyslog/UseSyslog/g; s/#VerbosePkgLists/VerbosePkgLists/g" /etc/pacman.conf

echo -e "$hostname" > /etc/hostname
useradd -g users -G wheel,video -m $username
echo -en "$root_password\n$root_password" | passwd
echo -en "$user_password\n$user_password" | passwd $username

systemctl enable NetworkManager.service fstrim.timer

journalctl --vacuum-size=100M --vacuum-time=2weeks

touch /etc/sysctl.d/99-swappiness.conf
echo 'vm.swappiness=20' > /etc/sysctl.d/99-swappiness.conf

touch /etc/udev/rules.d/backlight.rules
tee -a /etc/udev/rules.d/backlight.rules << END
ACTION=="add", SUBSYSTEM=="backlight", RUN+="/bin/chgrp video $sys$devpath/brightness", RUN+="/bin/chmod g+w $sys$devpath/brightness"
END

touch /etc/udev/rules.d/81-backlight.rules
tee -a /etc/udev/rules.d/81-backlight.rules << END
SUBSYSTEM=="backlight", ACTION=="add", KERNEL=="intel_backlight", ATTR{brightness}="9000"
END

mkdir -p /etc/pacman.d/hooks/
touch /etc/pacman.d/hooks/100-systemd-boot.hook
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
sed -i 's/^MODULES.*/MODULES=(intel_agp i915)/' /etc/mkinitcpio.conf
mkinitcpio -P
bootctl --path=/boot/ install

mkdir -p /boot/loader/
tee -a /boot/loader/loader.conf << END
default arch.conf
console-mode max
editor no
END

mkdir -p /boot/loader/entries/
touch /boot/loader/entries/arch.conf
tee -a /boot/loader/entries/arch.conf << END
title Arch Linux
linux /vmlinuz-linux
initrd /$cpu_model.img
initrd /initramfs-linux.img
options lsm=landlock,lockdown,yama,apparmor,bpf rd.luks.name=$(blkid -s UUID -o value "${part_root}")=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rd.luks.options=discard i915.fastboot=1 i915.enable_fbc=1 i915.enable_guc=2 nmi_watchdog=0 quiet rw
END

touch /boot/loader/entries/arch-zen.conf
tee -a /boot/loader/entries/arch-zen.conf << END
title Arch Linux Zen
linux /vmlinuz-linux-zen
initrd /$cpu_model.img
initrd /initramfs-linux-zen.img
options lsm=landlock,lockdown,yama,apparmor,bpf rd.luks.name=$(blkid -s UUID -o value "${part_root}")=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rd.luks.options=discard i915.fastboot=1 i915.enable_fbc=1 i915.enable_guc=2 nmi_watchdog=0 quiet rw
END

touch /boot/loader/entries/arch-lts.conf
tee -a /boot/loader/entries/arch-lts.conf << END
title Arch Linux LTS
linux /vmlinuz-linux-lts
initrd /$cpu_model.img
initrd /initramfs-linux-lts.img
options lsm=landlock,lockdown,yama,apparmor,bpf rd.luks.name=$(blkid -s UUID -o value "${part_root}")=cryptroot root=/dev/mapper/cryptroot rootflags=subvol=@ rd.luks.options=discard i915.fastboot=1 i915.enable_fbc=1 i915.enable_guc=2 nmi_watchdog=0 quiet rw
END

EOF
# END of Chroot
