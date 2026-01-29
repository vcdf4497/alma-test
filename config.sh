#!/bin/bash
# ==========================================================================
# ARCH LINUX PRO INSTALLER - BY MIDO
# Optimized for Proxmox, VM & Physical
# ==========================================================================

set -e

# --- Style ---
C_BLUE='\033[1;34m'
C_GREEN='\033[1;32m'
C_RED='\033[1;31m'
C_YELLOW='\033[1;33m'
C_NC='\033[0m'

header() {
    clear
    echo -e "${C_BLUE}"
    echo "  __  __ ___ ___   ___     ___ _  _ ___ _____ _   _    _    "
    echo " |  \/  |_ _|   \ / _ \   |_ _| \| / __|_   _/_\ | |  | |   "
    echo " | |\/| || || |) | (_) |   | || .  \__ \ | |/ _ \| |__| |__ "
    echo " |_|  |_|___|___/ \___/   |___|_|\_|___/ |_/_/ \_\____|____|"
    echo -e "                                         By MIDO${C_NC}\n"
}

trap 'echo -e "${C_RED}\n[!] Erreur détectée. Sortie...${C_NC}"; exit 1' ERR

header

# --- 0️⃣ Préparation Réseau & Heure ---
echo -e "${C_YELLOW}[*] Synchronisation de l'horloge système...${C_NC}"
timedatectl set-ntp true

# --- 1️⃣ Questionnaire Utilisateur ---
read -p "Nom d'utilisateur [user]: " USERNAME
USERNAME=${USERNAME:-user}

read -p "Nom de la machine [arch-vm]: " VMNAME
VMNAME=${VMNAME:-arch-vm}

read -sp "Mot de passe (Root & User) : " PASS
echo ""

# --- 2️⃣ Sélection du Disque ---
echo -e "\n${C_BLUE}[*] Disques disponibles :${C_NC}"
lsblk -d -n -o NAME,SIZE,MODEL | grep -v "loop"
echo ""
read -p "Entrez le nom du disque (ex: sda, vda, nvme0n1) : " DISK_NAME
DISK="/dev/$DISK_NAME"

if [ ! -b "$DISK" ]; then
    echo -e "${C_RED}[!] Le disque $DISK n'existe pas.${C_NC}"
    exit 1
fi

# --- 3️⃣ Options Supplémentaires ---
echo -e "\n${C_YELLOW}--- Options d'installation ---${C_NC}"
read -p "Installer Docker ? (y/n): " INSTALL_DOCKER
read -p "Installer NVM (Node Version Manager) ? (y/n): " INSTALL_NVM

# --- 4️⃣ Partitionnement Automatique ---
echo -e "\n${C_GREEN}[*] Nettoyage et partitionnement de $DISK...${C_NC}"
sgdisk --zap-all "$DISK"

if [ -d /sys/firmware/efi ]; then
    MODE="UEFI"
    sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
    sgdisk -n 2:0:+4G   -t 2:8200 -c 2:"SWAP" "$DISK"
    sgdisk -n 3:0:0     -t 3:8300 -c 3:"ROOT" "$DISK"
    P_EFI=$(lsblk -np "$DISK" | grep -E "${DISK}p?1" | head -n1 | awk '{print $1}')
    P_SWAP=$(lsblk -np "$DISK" | grep -E "${DISK}p?2" | head -n1 | awk '{print $1}')
    P_ROOT=$(lsblk -np "$DISK" | grep -E "${DISK}p?3" | head -n1 | awk '{print $1}')
else
    MODE="BIOS"
    parted -s "$DISK" mklabel msdos
    parted -s "$DISK" mkpart primary linux-swap 1MiB 4GiB
    parted -s "$DISK" mkpart primary ext4 4GiB 100%
    P_SWAP=$(lsblk -np "$DISK" | grep -E "${DISK}p?1" | head -n1 | awk '{print $1}')
    P_ROOT=$(lsblk -np "$DISK" | grep -E "${DISK}p?2" | head -n1 | awk '{print $1}')
fi

# --- 5️⃣ Formatage & Montage ---
mkswap "$P_SWAP" && swapon "$P_SWAP"
mkfs.ext4 -F "$P_ROOT"
mount "$P_ROOT" /mnt

if [ "$MODE" == "UEFI" ]; then
    mkfs.fat -F32 "$P_EFI"
    mkdir -p /mnt/boot/efi
    mount "$P_EFI" /mnt/boot/efi
fi

# --- 6️⃣ Pacstrap ---
echo -e "${C_GREEN}[*] Installation des paquets...${C_NC}"
PKGS="base linux linux-firmware base-devel networkmanager sudo xfce4 xfce4-goodies lightdm lightdm-gtk-greeter xterm xorg-server qemu-guest-agent"
[[ "$INSTALL_DOCKER" =~ ^[Yy]$ ]] && PKGS="$PKGS docker docker-compose"

pacstrap /mnt $PKGS

# --- 7️⃣ Configuration Chroot ---
genfstab -U /mnt >> /mnt/etc/fstab

arch-chroot /mnt /bin/bash <<EOF
set -e
# Localisation
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc
echo "fr_FR.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
echo "KEYMAP=fr" > /etc/vconsole.conf

# Réseau
echo "$VMNAME" > /etc/hostname

# Comptes
echo "root:$PASS" | chpasswd
useradd -m -G wheel,docker -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASS" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# NVM (si choisi)
if [[ "$INSTALL_NVM" =~ ^[Yy]$ ]]; then
    sudo -u "$USERNAME" bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
fi

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
systemctl enable qemu-guest-agent
[[ "$INSTALL_DOCKER" =~ ^[Yy]$ ]] && systemctl enable docker
EOF

# --- 8️⃣ Fin ---
header
echo -e "${C_GREEN}L'INSTALLATION EST TERMINÉE !${C_NC}"
echo -e "Mode : ${C_YELLOW}$MODE${C_NC} | Disque : ${C_YELLOW}$DISK${C_NC}"
echo -e "Utilisateur : ${C_YELLOW}$USERNAME${C_NC}"
echo -e "Proxmox Agent : ${C_GREEN}Activé${C_NC}"
echo ""
echo -e "${C_RED}Retirez l'ISO et appuyez sur Entrée pour reboot.${C_NC}"
read
reboot
