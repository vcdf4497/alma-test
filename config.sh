#!/bin/bash
# ==========================================================================
# ARCH LINUX PRO INSTALLER - MEGA ULTRA DÉBROUILLARD (adapté à tout espace de stockage)
# Optimized for Proxmox, VM & Physical
# ========================================================================

set -euo pipefail
IFS=$'\n\t'

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
    echo " |  \/  |_ _|   \/ _ \   |_ _| \| / __|_   _/_\ | |  | |   "
    echo " | |\/| || || |) | (_) |   | || .  \__ \ | |/ _ \| |__| |__ "
    echo " |_|  |_|___|___/ \___/   |___|_|\_|___/ |_/_/ \_\____|____|"
    echo -e "                                         By MIDO (MEGA)${C_NC}\n"
}

trap 'echo -e "${C_RED}\n[!] Erreur détectée. Sortie...${C_NC}"; exit 1' ERR

header

# Helper: read from the real terminal to be robust to redirections
_read() {
    local prompt="$1" default="$2" silent="$3" outvar="$4"
    if [ "$silent" = true ]; then
        read -s -p "$prompt" REPLY </dev/tty
        echo "" >/dev/tty
    else
        read -p "$prompt" REPLY </dev/tty
    fi
    if [ -n "$default" ] && [ -z "$REPLY" ]; then
        REPLY="$default"
    fi
    if [ -n "$outvar" ]; then
        printf -v "$outvar" "%s" "$REPLY"
    else
        printf "%s" "$REPLY"
    fi
}

# --- 0️⃣ Préparation Réseau & Heure ---
echo -e "${C_YELLOW}[*] Synchronisation de l'horloge système...${C_NC}"
timedatectl set-ntp true || true

# --- 1️⃣ Questionnaire Utilisateur ---
_read "Nom d'utilisateur [user]: " "user" false USERNAME
_read "Nom de la machine [arch-vm]: " "arch-vm" false VMNAME
_read "Mot de passe (Root & User) : " "" true PASS

# --- 2️⃣ Sélection du Disque (menu intelligent) ---
echo -e "\n${C_BLUE}[*] Disques disponibles :${C_NC}"
# List block devices (exclude loop and rom)
mapfile -t DISKS < <(lsblk -dn -o NAME,SIZE,MODEL,TYPE | grep -v loop | awk '$4=="disk" {print $1"|"$2"|"$3}')
if [ ${#DISKS[@]} -eq 0 ]; then
    echo -e "${C_RED}[!] Aucun disque détecté.${C_NC}"
    exit 1
fi

echo "Sélectionnez un disque (par numéro) ou entrez le nom/devpath :"
for i in "${!DISKS[@]}"; do
    IFS='|' read -r name size model <<< "${DISKS[$i]}"
    printf "%3d) %-12s %8s %s\n" $((i+1)) "/dev/$name" "$size" "$model"
done
_read "Choix (ex: 1 ou sda ou /dev/sda): " "" false DISK_INPUT

# Normalize disk selection
if [[ "$DISK_INPUT" =~ ^[0-9]+$ ]]; then
    idx=$((DISK_INPUT-1))
    if [ $idx -lt 0 ] || [ $idx -ge ${#DISKS[@]} ]; then
        echo -e "${C_RED}[!] Numéro invalide.${C_NC}"
        exit 1
    fi
    IFS='|' read -r selname selsize selmodel <<< "${DISKS[$idx]}"
    DISK="/dev/$selname"
elif [[ "$DISK_INPUT" == /* ]]; then
    DISK="$DISK_INPUT"
else
    DISK="/dev/$DISK_INPUT"
fi

if [ ! -b "$DISK" ]; then
    echo -e "${C_RED}[!] Le disque $DISK n'existe pas.${C_NC}"
    exit 1
fi

# --- 3️⃣ Options Supplémentaires ---
_read "Installer Docker ? (y/n): " "n" false INSTALL_DOCKER
_read "Installer NVM (Node Version Manager) ? (y/n): " "n" false INSTALL_NVM

# --- 4️⃣ Choix de l'environnement graphique ---
echo -e "\n${C_YELLOW}Choisissez l'environnement graphique :${C_NC}"
echo "1) GNOME"
echo "2) KDE (Plasma)"
echo "3) Classic (XFCE)"
echo "4) Aucun (serveur / minimal)"
_read "Sélection [1-4] : " "3" false DE_CHOICE

DE_PACKAGES=""
DM_SERVICE=""
case "$DE_CHOICE" in
  1)
    echo "=> GNOME sélectionné"
    DE_PACKAGES="gnome gnome-extra gdm"
    DM_SERVICE="gdm"
    ;; 
  2)
    echo "=> KDE Plasma sélectionné"
    DE_PACKAGES="plasma kde-applications sddm"
    DM_SERVICE="sddm"
    ;; 
  3)
    echo "=> Classic (XFCE) sélectionné"
    DE_PACKAGES="xfce4 xfce4-goodies lightdm lightdm-gtk-greeter"
    DM_SERVICE="lightdm"
    ;; 
  4)
    echo "=> Aucun environnement graphique (installation minimale)"
    DE_PACKAGES=""
    DM_SERVICE=""
    ;; 
  *)
    echo "Choix invalide, Classic (XFCE) par défaut"
    DE_PACKAGES="xfce4 xfce4-goodies lightdm lightdm-gtk-greeter"
    DM_SERVICE="lightdm"
    ;;
esac

# --- 5️⃣ Partitionnement intelligent (s'adapte à la taille du disque) ---
# Determine disk size in GiB
DISK_SIZE_B=$(lsblk -b -dn -o SIZE "$DISK")
DISK_SIZE_G=$((DISK_SIZE_B / 1024 / 1024 / 1024))

echo -e "\n${C_GREEN}[*] Disque sélectionné: ${C_YELLOW}$DISK${C_NC} (${DISK_SIZE_G} GiB)${C_NC}"

USE_SWAPFILE=false
SWAP_SIZE_MB=0
P_EFI=""
P_SWAP=""
P_ROOT=""

# Adaptive sizing rules
# - If disk < 20 GiB: create EFI (if needed), single root partition, use swapfile small (2G)
# - If disk between 20 and 60 GiB: create swap partition 2G, root rest
# - If disk >= 60 GiB: create swap partition 4G, root rest

if [ -d /sys/firmware/efi ]; then
    BOOT_MODE="UEFI"
else
    BOOT_MODE="BIOS"
fi

echo -e "${C_YELLOW}Mode de boot détecté: ${BOOT_MODE}${C_NC}"

if [ "$DISK_SIZE_G" -lt 20 ]; then
    echo -e "${C_YELLOW}Petit disque (<20GiB) : optimisation pour espace restreint${C_NC}"
    if [ "$BOOT_MODE" = "UEFI" ]; then
        sgdisk --zap-all "$DISK"
        sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
        sgdisk -n 2:0:0     -t 2:8300 -c 2:"ROOT" "$DISK"
        P_EFI=$(lsblk -np "$DISK" | grep -E "${DISK}p?1" | head -n1 | awk '{print $1}')
        P_ROOT=$(lsblk -np "$DISK" | grep -E "${DISK}p?2" | head -n1 | awk '{print $1}')
    else
        parted -s "$DISK" mklabel msdos
        parted -s "$DISK" mkpart primary ext4 1MiB 100%
        P_ROOT=$(lsblk -np "$DISK" | grep -E "${DISK}p?1" | head -n1 | awk '{print $1}')
    fi
    USE_SWAPFILE=true
    SWAP_SIZE_MB=2048
elif [ "$DISK_SIZE_G" -lt 60 ]; then
    echo -e "${C_YELLOW}Disque moyen : création de swap 2GiB et root${C_NC}"
    if [ "$BOOT_MODE" = "UEFI" ]; then
        sgdisk --zap-all "$DISK"
        sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
        sgdisk -n 2:0:+2G   -t 2:8200 -c 2:"SWAP" "$DISK"
        sgdisk -n 3:0:0     -t 3:8300 -c 3:"ROOT" "$DISK"
        P_EFI=$(lsblk -np "$DISK" | grep -E "${DISK}p?1" | head -n1 | awk '{print $1}')
        P_SWAP=$(lsblk -np "$DISK" | grep -E "${DISK}p?2" | head -n1 | awk '{print $1}')
        P_ROOT=$(lsblk -np "$DISK" | grep -E "${DISK}p?3" | head -n1 | awk '{print $1}')
    else
        parted -s "$DISK" mklabel msdos
        parted -s "$DISK" mkpart primary linux-swap 1MiB 2GiB
        parted -s "$DISK" mkpart primary ext4 2GiB 100%
        P_SWAP=$(lsblk -np "$DISK" | grep -E "${DISK}p?1" | head -n1 | awk '{print $1}')
        P_ROOT=$(lsblk -np "$DISK" | grep -E "${DISK}p?2" | head -n1 | awk '{print $1}')
    fi
    USE_SWAPFILE=false
    SWAP_SIZE_MB=0
else
    echo -e "${C_YELLOW}Grand disque : création de swap 4GiB et root${C_NC}"
    if [ "$BOOT_MODE" = "UEFI" ]; then
        sgdisk --zap-all "$DISK"
        sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
        sgdisk -n 2:0:+4G   -t 2:8200 -c 2:"SWAP" "$DISK"
        sgdisk -n 3:0:0     -t 3:8300 -c 3:"ROOT" "$DISK"
        P_EFI=$(lsblk -np "$DISK" | grep -E "${DISK}p?1" | head -n1 | awk '{print $1}')
        P_SWAP=$(lsblk -np "$DISK" | grep -E "${DISK}p?2" | head -n1 | awk '{print $1}')
        P_ROOT=$(lsblk -np "$DISK" | grep -E "${DISK}p?3" | head -n1 | awk '{print $1}')
    else
        parted -s "$DISK" mklabel msdos
        parted -s "$DISK" mkpart primary linux-swap 1MiB 4GiB
        parted -s "$DISK" mkpart primary ext4 4GiB 100%
        P_SWAP=$(lsblk -np "$DISK" | grep -E "${DISK}p?1" | head -n1 | awk '{print $1}')
        P_ROOT=$(lsblk -np "$DISK" | grep -E "${DISK}p?2" | head -n1 | awk '{print $1}')
    fi
    USE_SWAPFILE=false
    SWAP_SIZE_MB=0
fi

# Show partitions detected
echo -e "\n${C_BLUE}Partitions créées:${C_NC}"
[ -n "$P_EFI" ] && echo "EFI  : $P_EFI"
[ -n "$P_SWAP" ] && echo "SWAP : $P_SWAP"
[ -n "$P_ROOT" ] && echo "ROOT : $P_ROOT"
[ "$USE_SWAPFILE" = true ] && echo "SWAPFILE: /swapfile (${SWAP_SIZE_MB} MiB)"

_read "Confirmer et continuer ? Ceci va effacer le disque $DISK (oui/Non) : " "non" false CONFIRM
if [[ ! "$CONFIRM" =~ ^([oOyY]|oui|Oui)$ ]]; then
    echo "Annulation par l'utilisateur. Aucune modification effectuée."
    exit 0
fi

# --- 6️⃣ Formatage & Montage ---
if [ -n "$P_SWAP" ]; then
    echo -e "${C_GREEN}[*] Formatage de la partition swap: $P_SWAP${C_NC}"
mkswap "$P_SWAP" && swapon "$P_SWAP"
fi

if [ -n "$P_ROOT" ]; then
    echo -e "${C_GREEN}[*] Formatage de la partition root: $P_ROOT${C_NC}"
mkfs.ext4 -F "$P_ROOT"
mount "$P_ROOT" /mnt
else
    echo -e "${C_RED}[!] Aucune partition root détectée. Sortie...${C_NC}"
    exit 1
fi

if [ "$BOOT_MODE" = "UEFI" ] && [ -n "$P_EFI" ]; then
    echo -e "${C_GREEN}[*] Formatage et montage de l'EFI: $P_EFI${C_NC}"
mkfs.fat -F32 "$P_EFI"
mkdir -p /mnt/boot/efi
mount "$P_EFI" /mnt/boot/efi
fi

# If using swapfile, create placeholder (actual creation will be done inside chroot)
if [ "$USE_SWAPFILE" = true ]; then
    echo -e "${C_GREEN}[*] Un swapfile sera créé dans le système après pacstrap (${SWAP_SIZE_MB} MiB).${C_NC}"
fi

# --- 7️⃣ Pacstrap ---
echo -e "${C_GREEN}[*] Installation des paquets...${C_NC}"
PKGS=(base linux linux-firmware base-devel networkmanager sudo xorg-server qemu-guest-agent firefox)
# add desktop environment packages
if [ -n "$DE_PACKAGES" ]; then
    read -r -a EXTRA <<< "$DE_PACKAGES"
    PKGS=("${PKGS[@]}" "${EXTRA[@]}")
fi
if [[ "$INSTALL_DOCKER" =~ ^[YyOo] ]]; then
    PKGS=("${PKGS[@]}" docker docker-compose)
fi

pacstrap /mnt "${PKGS[@]}"

# --- 8️⃣ Configuration Chroot ---
# Pass environment variables to heredoc by expanding them now (intentional)
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
useradd -m -G wheel${DE_PACKAGES:+,docker} -s /bin/bash "$USERNAME" || true
echo "$USERNAME:$PASS" | chpasswd
if ! grep -q '^%wheel' /etc/sudoers; then
  echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
fi

# NVM (si choisi)
if [[ "$INSTALL_NVM" =~ ^[YyOo]$ ]]; then
    sudo -u "$USERNAME" bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash"
fi

# Swapfile creation if selected
if [ "$USE_SWAPFILE" = true ]; then
    echo -e "${C_GREEN}[*] Création du swapfile (${SWAP_SIZE_MB} MiB)...${C_NC}"
fallocate -l ${SWAP_SIZE_MB}M /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=${SWAP_SIZE_MB}
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo "/swapfile none swap defaults 0 0" >> /etc/fstab
fi

# Bootloader
pacman -S --noconfirm grub
if [ "$BOOT_MODE" == "UEFI" ]; then
    pacman -S --noconfirm efibootmgr
    mkdir -p /boot/efi
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB
else
    grub-install --target=i386-pc "$DISK"
fi
grub-mkconfig -o /boot/grub/grub.cfg

# Services
systemctl enable NetworkManager
if [ -n "$DM_SERVICE" ]; then
  systemctl enable "$DM_SERVICE"
fi
systemctl enable qemu-guest-agent
if [[ "$INSTALL_DOCKER" =~ ^[YyOo]$ ]]; then
  systemctl enable docker
fi
EOF

# --- 9️⃣ Fin ---
header
echo -e "${C_GREEN}L'INSTALLATION EST TERMINÉE !${C_NC}"
echo -e "Mode : ${C_YELLOW}$BOOT_MODE${C_NC} | Disque : ${C_YELLOW}$DISK${C_NC}"
echo -e "Utilisateur : ${C_YELLOW}$USERNAME${C_NC}"
echo -e "Environnement installé : ${C_YELLOW}${DE_CHOICE}${C_NC}"
echo ""
echo -e "${C_RED}Retirez l'ISO et appuyez sur Entrée pour reboot.${C_NC}"
read -r </dev/tty
reboot
