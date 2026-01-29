#!/bin/bash
# ==========================================================================
# ARCH LINUX ULTIMATE VM INSTALLER - BY MIDO
# Support: BIOS & UEFI | XFCE | Auto-Partitioning
# ==========================================================================

set -e

# --- Couleurs et Style ---
C_BLUE='\033[1;34m'
C_GREEN='\033[1;32m'
C_RED='\033[1;31m'
C_YELLOW='\033[1;33m'
C_NC='\033[0m'

header() {
    clear
    echo -e "${C_BLUE}###########################################${C_NC}"
    echo -e "${C_BLUE}#       ARCH INSTALLER - BY MIDO          #${C_NC}"
    echo -e "${C_BLUE}###########################################${C_NC}"
    echo ""
}

error_exit() {
    echo -e "${C_RED}[ERREUR] Ligne $1 : L'installation a échoué.${C_NC}"
    exit 1
}

trap 'error_exit $LINENO' ERR

header

# --- 1️⃣ Questionnaire ---
read -p "Nom de la machine (hostname) [mido-arch]: " VMNAME
VMNAME=${VMNAME:-mido-arch}

echo -e "${C_YELLOW}Configuration du mot de passe unique (root & user)...${C_NC}"
read -sp "Entrez le mot de passe : " PASS
echo
read -sp "Confirmez le mot de passe : " PASS2
echo
[[ "$PASS" != "$PASS2" ]] && echo -e "${C_RED}Mots de passe différents !${C_NC}" && exit 1

# --- 2️⃣ Préparation Disque ---
DISK=$(lsblk -d -n -b -o NAME,SIZE,TYPE | grep 'disk' | sort -k2 -nr | head -n1 | awk '{print "/dev/"$1}')
echo -e "${C_GREEN}[+] Disque cible : $DISK${C_NC}"

# Nettoyage complet
sgdisk --zap-all "$DISK"
wipefs -a "$DISK"

# Détection Mode (UEFI/BIOS)
if [ -d /sys/firmware/efi ]; then
    MODE="UEFI"
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
    sgdisk -n 2:0:+4G   -t 2:8200 -c 2:"SWAP" "$DISK"
    sgdisk -n 3:0:0     -t 3:8300 -c 3:"ROOT" "$DISK"
    P_EFI="${DISK}1"
    P_SWAP="${DISK}2"
    P_ROOT="${DISK}3"
    [[ "$DISK" == *"nvme"* ]] && { P_EFI="${DISK}p1"; P_SWAP="${DISK}p2"; P_ROOT="${DISK}p3"; }
else
    MODE="BIOS"
    parted -s "$DISK" mklabel msdos
    parted -s "$DISK" mkpart primary linux-swap 1MiB 4GiB
    parted -s "$DISK" mkpart primary ext4 4GiB 100%
    P_SWAP="${DISK}1"
    P_ROOT="${DISK}2"
fi

# --- 3️⃣ Formatage ---
echo -e "${C_GREEN}[+] Formatage en cours...${C_NC}"
mkswap "$P_SWAP" && swapon "$P_SWAP"
mkfs.ext4 -F "$P_ROOT"
mount "$P_ROOT" /mnt

if [ "$MODE" == "UEFI" ]; then
    mkfs.fat -F32 "$P_EFI"
    mkdir -p /mnt/boot/efi
    mount "$P_EFI" /mnt/boot/efi
fi

# --- 4️⃣ Pacstrap ---
echo -e "${C_GREEN}[+] Installation du système de base + XFCE...${C_NC}"
pacstrap /mnt base linux linux-firmware base-devel networkmanager sudo xfce4 xfce4-goodies lightdm lightdm-gtk-greeter xterm xorg-server

# --- 5️⃣ Configuration (Chroot) ---
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF
set -e
# Locale & Time
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc
echo "fr_FR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
echo "KEYMAP=fr" > /etc/vconsole.conf

# Hostname
echo "$VMNAME" > /etc/hostname

# Users
echo "root:$PASS" | chpasswd
useradd -m -G wheel -s /bin/bash mido
echo "mido:$PASS" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Bootloader
pacman -S --noconfirm grub
if [ "$MODE" == "UEFI" ]; then
    pacman -S --noconfirm efibootmgr
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
    grub-install --target=i386-pc "$DISK"
fi
grub-mkconfig -o /boot/grub/grub.cfg

# Services
systemctl enable NetworkManager
systemctl enable lightdm
EOF

# --- 6️⃣ Fin ---
header
echo -e "${C_GREEN}INSTALLATION TERMINÉE PAR MIDO !${C_NC}"
echo -e "Utilisateur créé : ${C_YELLOW}mido${C_NC}"
echo -e "Mode de boot : ${C_YELLOW}$MODE${C_NC}"
echo ""
echo -e "${C_RED}Retirez l'ISO et appuyez sur ENTREE pour redémarrer.${C_NC}"
read
reboot
