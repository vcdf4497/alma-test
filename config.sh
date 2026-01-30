#!/bin/bash
# ==========================================================================
# ARCH LINUX PRO INSTALLER - Version JSON avec gestion avancée des tailles
# Optimized for Proxmox, VM & Physical
# ==========================================================================

set -euo pipefail
IFS=$'\n\t'

# --- Style ---
C_BLUE='\033[1;34m'
C_GREEN='\033[1;32m'
C_RED='\033[1;31m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[1;36m'
C_NC='\033[0m'

header() {
    clear
    echo -e "${C_BLUE}"
    echo "  __  __ ___ ___   ___     ___ _  _ ___ _____ _   _    _    "
    echo " |  \/  |_ _|   \/ _ \   |_ _| \| / __|_   _/_\ | |  | |   "
    echo " | |\/| || || |) | (_) |   | || .  \__ \ | |/ _ \| |__| |__ "
    echo " |_|  |_|___|___/ \___/   |___|_|\_|___/ |_/_/ \_\____|____|"
    echo -e "                                    By MIDO v2.0 (JSON)${C_NC}\n"
}

trap 'echo -e "${C_RED}\n[!] Erreur détectée ligne $LINENO. Sortie...${C_NC}"; exit 1' ERR

# Helper: lecture sécurisée depuis le terminal
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

# Helper: conversion de taille en octets
# Supporte: 123456789, 10G, 512M, 2T, 100K, etc.
size_to_bytes() {
    local size="$1"
    local num unit
    
    # Si c'est déjà un nombre pur (en octets)
    if [[ "$size" =~ ^[0-9]+$ ]]; then
        echo "$size"
        return
    fi
    
    # Extraire nombre et unité
    num=$(echo "$size" | sed 's/[^0-9.]//g')
    unit=$(echo "$size" | sed 's/[0-9.]//g' | tr '[:lower:]' '[:upper:]')
    
    # Si pas d'unité, c'est des octets
    if [ -z "$unit" ]; then
        echo "${num%.*}"
        return
    fi
    
    # Conversion selon l'unité
    case "$unit" in
        K|KB|KIB)
            echo "$num * 1024" | bc | cut -d. -f1
            ;;
        M|MB|MIB)
            echo "$num * 1024 * 1024" | bc | cut -d. -f1
            ;;
        G|GB|GIB)
            echo "$num * 1024 * 1024 * 1024" | bc | cut -d. -f1
            ;;
        T|TB|TIB)
            echo "$num * 1024 * 1024 * 1024 * 1024" | bc | cut -d. -f1
            ;;
        *)
            echo "${num%.*}"
            ;;
    esac
}

# Helper: conversion d'octets vers format lisible
bytes_to_human() {
    local bytes="$1"
    local units=("B" "K" "M" "G" "T")
    local unit=0
    local size=$bytes
    
    while (( $(echo "$size >= 1024" | bc -l) )) && (( unit < 4 )); do
        size=$(echo "scale=2; $size / 1024" | bc)
        ((unit++))
    done
    
    printf "%.1f%s" "$size" "${units[$unit]}"
}

header

# Vérifier les dépendances (jq n'est plus nécessaire)
for cmd in bc lsblk sgdisk parted; do
    if ! command -v "$cmd" &>/dev/null; then
        echo -e "${C_RED}[!] Commande manquante: $cmd${C_NC}"
        echo "Installation: pacman -S bc util-linux gptfdisk parted"
        exit 1
    fi
done

# --- 0️⃣ Préparation Réseau & Heure ---
echo -e "${C_YELLOW}[*] Synchronisation de l'horloge système...${C_NC}"
timedatectl set-ntp true 2>/dev/null || true

# --- 1️⃣ Questionnaire Utilisateur ---
echo -e "${C_CYAN}=== Configuration de base ===${C_NC}"
_read "Nom d'utilisateur [user]: " "user" false USERNAME
_read "Nom de la machine [arch-vm]: " "arch-vm" false VMNAME
_read "Mot de passe (Root & User): " "" true PASS
echo ""

# --- 2️⃣ Sélection du Disque avec JSON (sans jq) ---
echo -e "\n${C_BLUE}[*] Analyse des disques disponibles...${C_NC}"

# Récupérer les disques en JSON
DISKS_JSON=$(lsblk -J -d -o NAME,SIZE,TYPE,MODEL,TRAN 2>/dev/null)

# Parser le JSON sans jq (méthode compatible ISO Arch)
declare -a DISK_NAMES DISK_SIZES DISK_MODELS DISK_TRANS

# Extraction avec grep et sed
while IFS= read -r line; do
    if [[ "$line" =~ \"name\":[[:space:]]*\"([^\"]+)\" ]]; then
        name="${BASH_REMATCH[1]}"
    fi
    if [[ "$line" =~ \"size\":[[:space:]]*\"([^\"]+)\" ]]; then
        size="${BASH_REMATCH[1]}"
    fi
    if [[ "$line" =~ \"type\":[[:space:]]*\"([^\"]+)\" ]]; then
        type="${BASH_REMATCH[1]}"
    fi
    if [[ "$line" =~ \"model\":[[:space:]]*\"([^\"]+)\" ]]; then
        model="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ \"model\":[[:space:]]*null ]]; then
        model="N/A"
    fi
    if [[ "$line" =~ \"tran\":[[:space:]]*\"([^\"]+)\" ]]; then
        tran="${BASH_REMATCH[1]}"
    elif [[ "$line" =~ \"tran\":[[:space:]]*null ]]; then
        tran="N/A"
    fi
    
    # Si on trouve un "}" et qu'on a un type "disk", on enregistre
    if [[ "$line" =~ \} ]] && [[ "$type" == "disk" ]] && [[ -n "$name" ]]; then
        DISK_NAMES+=("$name")
        DISK_SIZES+=("$size")
        DISK_MODELS+=("${model:-N/A}")
        DISK_TRANS+=("${tran:-N/A}")
        name="" size="" type="" model="" tran=""
    fi
done <<< "$DISKS_JSON"

if [ ${#DISK_NAMES[@]} -eq 0 ]; then
    echo -e "${C_RED}[!] Aucun disque détecté.${C_NC}"
    exit 1
fi

echo -e "${C_GREEN}Disques disponibles:${C_NC}\n"
printf "${C_YELLOW}%4s  %-15s  %10s  %-8s  %s${C_NC}\n" "N°" "DEVICE" "SIZE" "BUS" "MODEL"
echo "────────────────────────────────────────────────────────────────"

for i in "${!DISK_NAMES[@]}"; do
    printf "%4d) %-15s  %10s  %-8s  %s\n" \
        $((i+1)) \
        "/dev/${DISK_NAMES[$i]}" \
        "${DISK_SIZES[$i]}" \
        "${DISK_TRANS[$i]}" \
        "${DISK_MODELS[$i]}"
done

echo ""
_read "Sélection (numéro, nom ou chemin): " "" false DISK_INPUT

# Normalisation du choix
if [[ "$DISK_INPUT" =~ ^[0-9]+$ ]]; then
    idx=$((DISK_INPUT-1))
    if [ $idx -lt 0 ] || [ $idx -ge ${#DISK_NAMES[@]} ]; then
        echo -e "${C_RED}[!] Numéro invalide.${C_NC}"
        exit 1
    fi
    DISK="/dev/${DISK_NAMES[$idx]}"
    DISK_SIZE_STR="${DISK_SIZES[$idx]}"
elif [[ "$DISK_INPUT" == /* ]]; then
    DISK="$DISK_INPUT"
    # Récupérer la taille
    DISK_SIZE_STR=$(lsblk -d -n -o SIZE "$DISK" 2>/dev/null || echo "0")
else
    DISK="/dev/$DISK_INPUT"
    DISK_SIZE_STR=$(lsblk -d -n -o SIZE "$DISK" 2>/dev/null || echo "0")
fi

# Vérifier que le disque existe
if [ ! -b "$DISK" ]; then
    echo -e "${C_RED}[!] Le disque $DISK n'existe pas.${C_NC}"
    exit 1
fi

# Convertir la taille en octets puis en GiB
DISK_SIZE_BYTES=$(size_to_bytes "$DISK_SIZE_STR")
DISK_SIZE_G=$(echo "$DISK_SIZE_BYTES / 1024 / 1024 / 1024" | bc)

echo -e "\n${C_GREEN}✓ Disque sélectionné: ${C_YELLOW}$DISK${C_NC}"
echo -e "  Taille: ${C_CYAN}$DISK_SIZE_STR${C_NC} ($(bytes_to_human $DISK_SIZE_BYTES), ${DISK_SIZE_G} GiB)"

# --- 3️⃣ Options Supplémentaires ---
echo -e "\n${C_CYAN}=== Options d'installation ===${C_NC}"
_read "Installer Docker ? (y/n) [n]: " "n" false INSTALL_DOCKER
_read "Installer NVM (Node) ? (y/n) [n]: " "n" false INSTALL_NVM

# --- 4️⃣ Choix de l'environnement graphique ---
echo -e "\n${C_CYAN}=== Environnement graphique ===${C_NC}"
echo "1) GNOME"
echo "2) KDE Plasma"
echo "3) XFCE (Classic)"
echo "4) Aucun (minimal/serveur)"
_read "Choix [1-4]: " "3" false DE_CHOICE

DE_PACKAGES=""
DM_SERVICE=""
case "$DE_CHOICE" in
    1)
        echo -e "${C_GREEN}→ GNOME sélectionné (minimal)${C_NC}"
        DE_PACKAGES="gdm"
        DM_SERVICE="gdm"
        ;;
    2)
        echo -e "${C_GREEN}→ KDE Plasma sélectionné (minimal)${C_NC}"
        DE_PACKAGES="sddm plasma-desktop konsole dolphin"
        DM_SERVICE="sddm"
        ;;
    3)
        echo -e "${C_GREEN}→ XFCE sélectionné${C_NC}"
        DE_PACKAGES="lightdm lightdm-gtk-greeter xfce4-session xfce4-panel thunar xfce4-terminal"
        DM_SERVICE="lightdm"
        ;;
    4)
        echo -e "${C_GREEN}→ Installation minimale${C_NC}"
        DE_PACKAGES=""
        DM_SERVICE=""
        ;;
    *)
        echo -e "${C_YELLOW}⚠ Choix invalide, XFCE par défaut${C_NC}"
        DE_PACKAGES="lightdm lightdm-gtk-greeter xfce4-session xfce4-panel thunar xfce4-terminal"
        DM_SERVICE="lightdm"
        ;;
esac

# --- 5️⃣ Partitionnement intelligent ---
echo -e "\n${C_CYAN}=== Planification du partitionnement ===${C_NC}"

# Détection du mode de boot
if [ -d /sys/firmware/efi ]; then
    BOOT_MODE="UEFI"
else
    BOOT_MODE="BIOS"
fi
echo -e "Mode de boot: ${C_YELLOW}$BOOT_MODE${C_NC}"

USE_SWAPFILE=false
SWAP_SIZE_MB=0
P_EFI=""
P_SWAP=""
P_ROOT=""

# Règles adaptatives selon la taille
if [ "$DISK_SIZE_G" -lt 20 ]; then
    echo -e "${C_YELLOW}Stratégie: Petit disque (<20 GiB)${C_NC}"
    echo "  → EFI 512M (si UEFI)"
    echo "  → ROOT (reste)"
    echo "  → SWAPFILE 2G"
    USE_SWAPFILE=true
    SWAP_SIZE_MB=2048
    SCHEME="small"
elif [ "$DISK_SIZE_G" -lt 60 ]; then
    echo -e "${C_YELLOW}Stratégie: Disque moyen (20-60 GiB)${C_NC}"
    echo "  → EFI 512M (si UEFI)"
    echo "  → SWAP 2G"
    echo "  → ROOT (reste)"
    USE_SWAPFILE=false
    SWAP_SIZE_MB=0
    SCHEME="medium"
else
    echo -e "${C_YELLOW}Stratégie: Grand disque (≥60 GiB)${C_NC}"
    echo "  → EFI 512M (si UEFI)"
    echo "  → SWAP 4G"
    echo "  → ROOT (reste)"
    USE_SWAPFILE=false
    SWAP_SIZE_MB=0
    SCHEME="large"
fi

echo ""
_read "⚠️  ATTENTION: Toutes les données de $DISK seront EFFACÉES. Confirmer ? (oui/non): " "non" false CONFIRM

if [[ ! "$CONFIRM" =~ ^(oui|OUI|Oui|yes|YES|Yes|y|Y|o|O)$ ]]; then
    echo -e "${C_RED}Installation annulée.${C_NC}"
    exit 0
fi

# --- 6️⃣ Nettoyage du disque avant partitionnement ---
echo -e "\n${C_YELLOW}[*] Nettoyage du disque $DISK...${C_NC}"

# Démonter toutes les partitions du disque
for mount_point in $(mount | grep "^$DISK" | awk '{print $3}'); do
    echo "  → Démontage de $mount_point"
    umount -R "$mount_point" 2>/dev/null || true
done

# Désactiver le swap sur ce disque
swapoff "${DISK}"* 2>/dev/null || true
swapoff -a 2>/dev/null || true

# Tuer tous les processus utilisant le disque
fuser -km "$DISK" 2>/dev/null || true

# Attendre un peu
sleep 2

# --- 7️⃣ Partitionnement effectif ---
echo -e "\n${C_GREEN}[*] Partitionnement de $DISK...${C_NC}"

if [ "$BOOT_MODE" = "UEFI" ]; then
    # Mode UEFI avec GPT
    echo "  → Effacement des signatures..."
    wipefs -af "$DISK" 2>/dev/null || true
    dd if=/dev/zero of="$DISK" bs=512 count=1 conv=notrunc 2>/dev/null || true
    
    echo "  → Création de la table GPT..."
    sgdisk --zap-all "$DISK" 2>/dev/null || true
    sgdisk --clear "$DISK" 2>/dev/null || true
    
    echo "  → Création des partitions..."
    case "$SCHEME" in
        small)
            sgdisk -n 1:0:+512M  -t 1:ef00 -c 1:"EFI"  "$DISK"
            sgdisk -n 2:0:0      -t 2:8300 -c 2:"ROOT" "$DISK"
            ;;
        medium)
            sgdisk -n 1:0:+512M  -t 1:ef00 -c 1:"EFI"  "$DISK"
            sgdisk -n 2:0:+2G    -t 2:8200 -c 2:"SWAP" "$DISK"
            sgdisk -n 3:0:0      -t 3:8300 -c 3:"ROOT" "$DISK"
            ;;
        large)
            sgdisk -n 1:0:+512M  -t 1:ef00 -c 1:"EFI"  "$DISK"
            sgdisk -n 2:0:+4G    -t 2:8200 -c 2:"SWAP" "$DISK"
            sgdisk -n 3:0:0      -t 3:8300 -c 3:"ROOT" "$DISK"
            ;;
    esac
    
    # Recharger la table de partitions et attendre
    echo "  → Actualisation de la table de partitions..."
    partprobe "$DISK" 2>/dev/null || true
    udevadm settle 2>/dev/null || true
    sleep 3
    
    # Forcer la relecture du kernel
    blockdev --rereadpt "$DISK" 2>/dev/null || true
    sleep 1
    
    # Détection des partitions créées
    P_EFI="${DISK}1"
    if [ "$SCHEME" = "small" ]; then
        P_ROOT="${DISK}2"
    else
        P_SWAP="${DISK}2"
        P_ROOT="${DISK}3"
    fi
    
    # Gestion des disques NVMe (p1, p2, p3)
    if [[ "$DISK" =~ nvme ]]; then
        P_EFI="${DISK}p1"
        if [ "$SCHEME" = "small" ]; then
            P_ROOT="${DISK}p2"
        else
            P_SWAP="${DISK}p2"
            P_ROOT="${DISK}p3"
        fi
    fi
    
else
    # Mode BIOS avec MBR
    echo "  → Effacement des signatures..."
    wipefs -af "$DISK" 2>/dev/null || true
    dd if=/dev/zero of="$DISK" bs=512 count=1 conv=notrunc 2>/dev/null || true
    
    echo "  → Création de la table MBR..."
    parted -s "$DISK" mklabel msdos
    
    echo "  → Création des partitions..."
    case "$SCHEME" in
        small)
            parted -s "$DISK" mkpart primary ext4 1MiB 100%
            P_ROOT="${DISK}1"
            ;;
        medium)
            parted -s "$DISK" mkpart primary linux-swap 1MiB 2GiB
            parted -s "$DISK" mkpart primary ext4 2GiB 100%
            P_SWAP="${DISK}1"
            P_ROOT="${DISK}2"
            ;;
        large)
            parted -s "$DISK" mkpart primary linux-swap 1MiB 4GiB
            parted -s "$DISK" mkpart primary ext4 4GiB 100%
            P_SWAP="${DISK}1"
            P_ROOT="${DISK}2"
            ;;
    esac
    
    # Recharger la table de partitions et attendre
    echo "  → Actualisation de la table de partitions..."
    partprobe "$DISK" 2>/dev/null || true
    udevadm settle 2>/dev/null || true
    sleep 3
    
    # Forcer la relecture du kernel
    blockdev --rereadpt "$DISK" 2>/dev/null || true
    sleep 1
    
    # Gestion NVMe pour BIOS aussi
    if [[ "$DISK" =~ nvme ]]; then
        if [ "$SCHEME" = "small" ]; then
            P_ROOT="${DISK}p1"
        else
            P_SWAP="${DISK}p1"
            P_ROOT="${DISK}p2"
        fi
    fi
fi

# Vérifier que les partitions existent vraiment
echo "  → Vérification des partitions..."
for part in "$P_EFI" "$P_SWAP" "$P_ROOT"; do
    if [ -n "$part" ] && [ ! -b "$part" ]; then
        echo -e "${C_YELLOW}  ⚠ Partition $part non détectée, attente supplémentaire...${C_NC}"
        sleep 3
        partprobe "$DISK" 2>/dev/null || true
        udevadm settle 2>/dev/null || true
        sleep 2
        break
    fi
done

# Affichage des partitions
echo -e "\n${C_BLUE}Partitions créées:${C_NC}"
[ -n "$P_EFI" ]  && echo -e "  ${C_GREEN}EFI  →${C_NC} $P_EFI"
[ -n "$P_SWAP" ] && echo -e "  ${C_GREEN}SWAP →${C_NC} $P_SWAP"
[ -n "$P_ROOT" ] && echo -e "  ${C_GREEN}ROOT →${C_NC} $P_ROOT"
[ "$USE_SWAPFILE" = true ] && echo -e "  ${C_GREEN}SWAPFILE →${C_NC} /swapfile (${SWAP_SIZE_MB} MiB)"

sleep 2

# --- 7️⃣ Formatage & Montage ---
echo -e "\n${C_GREEN}[*] Formatage des partitions...${C_NC}"

if [ -n "$P_SWAP" ]; then
    echo "  → Formatage SWAP: $P_SWAP"
    mkswap "$P_SWAP"
    swapon "$P_SWAP"
fi

if [ -z "$P_ROOT" ]; then
    echo -e "${C_RED}[!] Partition ROOT introuvable!${C_NC}"
    exit 1
fi

echo "  → Formatage ROOT: $P_ROOT"
mkfs.ext4 -F "$P_ROOT"
mount "$P_ROOT" /mnt

if [ "$BOOT_MODE" = "UEFI" ] && [ -n "$P_EFI" ]; then
    echo "  → Formatage EFI: $P_EFI"
    mkfs.fat -F32 "$P_EFI"
    mkdir -p /mnt/boot/efi
    mount "$P_EFI" /mnt/boot/efi
fi

# --- 8️⃣ Pacstrap ---
echo -e "\n${C_GREEN}[*] Installation du système de base...${C_NC}"

PKGS=(
    base linux linux-firmware
    base-devel
    networkmanager
    sudo
    vim nano
    man-db man-pages
    bash-completion
)

# Ajouter les outils pour VM si détecté
if systemd-detect-virt -q; then
    VIRT_TYPE=$(systemd-detect-virt)
    echo -e "  ${C_CYAN}Machine virtuelle détectée: $VIRT_TYPE${C_NC}"
    case "$VIRT_TYPE" in
        kvm|qemu)
            PKGS+=(qemu-guest-agent)
            ;;
        vmware)
            PKGS+=(open-vm-tools)
            ;;
        oracle)
            PKGS+=(virtualbox-guest-utils)
            ;;
    esac
fi

# Desktop Environment
INSTALL_FULL_DE=false
if [ -n "$DE_PACKAGES" ]; then
    PKGS+=(xorg-server)
    read -r -a DE_ARRAY <<< "$DE_PACKAGES"
    PKGS+=("${DE_ARRAY[@]}")
    PKGS+=(firefox)
    
    # Proposer l'installation complète du groupe
    echo ""
    case "$DE_CHOICE" in
        1)
            _read "Installer le groupe complet 'gnome' (plus de paquets) ? (y/n) [n]: " "n" false INSTALL_FULL_DE
            ;;
        2)
            _read "Installer le groupe complet 'plasma' (plus de paquets) ? (y/n) [n]: " "n" false INSTALL_FULL_DE
            ;;
    esac
fi

# Docker
if [[ "$INSTALL_DOCKER" =~ ^[YyOo] ]]; then
    PKGS+=(docker docker-compose)
fi

# Installation des paquets de base
echo -e "\n${C_GREEN}[*] Installation du système (${#PKGS[@]} paquets)...${C_NC}"
pacstrap -K /mnt "${PKGS[@]}"

# Installation des groupes complets si demandé
if [[ "$INSTALL_FULL_DE" =~ ^[YyOo]$ ]]; then
    echo -e "${C_GREEN}[*] Installation du groupe complet DE (cela peut prendre du temps)...${C_NC}"
    case "$DE_CHOICE" in
        1)
            # Installer le groupe gnome en répondant automatiquement "oui" à tout
            yes "" | pacstrap /mnt gnome 2>/dev/null || pacstrap /mnt gnome
            ;;
        2)
            yes "" | pacstrap /mnt plasma 2>/dev/null || pacstrap /mnt plasma
            ;;
    esac
fi

# --- 9️⃣ Configuration système ---
echo -e "\n${C_GREEN}[*] Génération de fstab...${C_NC}"
genfstab -U /mnt >> /mnt/etc/fstab

echo -e "${C_GREEN}[*] Configuration du système...${C_NC}"

# Passer les variables au chroot
cat > /mnt/tmp/install_vars.sh <<EOVARS
VMNAME="$VMNAME"
USERNAME="$USERNAME"
PASS="$PASS"
INSTALL_NVM="$INSTALL_NVM"
INSTALL_DOCKER="$INSTALL_DOCKER"
USE_SWAPFILE=$USE_SWAPFILE
SWAP_SIZE_MB=$SWAP_SIZE_MB
BOOT_MODE="$BOOT_MODE"
DISK="$DISK"
DM_SERVICE="$DM_SERVICE"
EOVARS

# Script de configuration dans le chroot
cat > /mnt/tmp/setup.sh <<'EOSCRIPT'
#!/bin/bash
set -e
source /tmp/install_vars.sh

# Timezone et locale
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc

# Locale française
cat > /etc/locale.gen <<EOF
fr_FR.UTF-8 UTF-8
en_US.UTF-8 UTF-8
EOF
locale-gen
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf
echo "KEYMAP=fr" > /etc/vconsole.conf

# Hostname
echo "$VMNAME" > /etc/hostname
cat > /etc/hosts <<EOF
127.0.0.1    localhost
::1          localhost
127.0.1.1    $VMNAME.localdomain $VMNAME
EOF

# Utilisateurs
echo "root:$PASS" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME" 2>/dev/null || true
echo "$USERNAME:$PASS" | chpasswd

# Docker group
if [[ "$INSTALL_DOCKER" =~ ^[YyOo]$ ]]; then
    usermod -aG docker "$USERNAME" 2>/dev/null || true
fi

# Sudo pour wheel
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# NVM (Node Version Manager)
if [[ "$INSTALL_NVM" =~ ^[YyOo]$ ]]; then
    echo "Installation de NVM pour $USERNAME..."
    sudo -u "$USERNAME" bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash'
fi

# Swapfile si nécessaire
if [ "$USE_SWAPFILE" = true ]; then
    echo "Création du swapfile (${SWAP_SIZE_MB} MiB)..."
    dd if=/dev/zero of=/swapfile bs=1M count=$SWAP_SIZE_MB status=progress
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap defaults 0 0" >> /etc/fstab
fi

# Bootloader
pacman -S --noconfirm grub
if [ "$BOOT_MODE" = "UEFI" ]; then
    pacman -S --noconfirm efibootmgr
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

# Services VM
if systemctl list-unit-files | grep -q qemu-guest-agent; then
    systemctl enable qemu-guest-agent
fi
if systemctl list-unit-files | grep -q vmtoolsd; then
    systemctl enable vmtoolsd
fi
if systemctl list-unit-files | grep -q vboxservice; then
    systemctl enable vboxservice
fi

# Docker
if [[ "$INSTALL_DOCKER" =~ ^[YyOo]$ ]]; then
    systemctl enable docker
fi

rm -f /tmp/install_vars.sh /tmp/setup.sh
EOSCRIPT

chmod +x /mnt/tmp/setup.sh
arch-chroot /mnt /tmp/setup.sh

# --- 🎉 Fin ---
header
echo -e "${C_GREEN}╔════════════════════════════════════════════════════════╗${C_NC}"
echo -e "${C_GREEN}║                                                        ║${C_NC}"
echo -e "${C_GREEN}║          ✓ INSTALLATION TERMINÉE AVEC SUCCÈS !        ║${C_NC}"
echo -e "${C_GREEN}║                                                        ║${C_NC}"
echo -e "${C_GREEN}╚════════════════════════════════════════════════════════╝${C_NC}"
echo ""
echo -e "  ${C_CYAN}Disque:${C_NC}         $DISK (${DISK_SIZE_STR})"
echo -e "  ${C_CYAN}Mode boot:${C_NC}      $BOOT_MODE"
echo -e "  ${C_CYAN}Hostname:${C_NC}       $VMNAME"
echo -e "  ${C_CYAN}Utilisateur:${C_NC}    $USERNAME"
echo -e "  ${C_CYAN}Desktop:${C_NC}        ${DE_CHOICE}"
[[ "$INSTALL_DOCKER" =~ ^[YyOo]$ ]] && echo -e "  ${C_CYAN}Docker:${C_NC}         ✓ Installé"
[[ "$INSTALL_NVM" =~ ^[YyOo]$ ]] && echo -e "  ${C_CYAN}NVM:${C_NC}            ✓ Installé"
echo ""
echo -e "${C_YELLOW}[!] Retirez le média d'installation${C_NC}"
echo -e "${C_YELLOW}[!] Appuyez sur Entrée pour redémarrer...${C_NC}"
read -r </dev/tty

umount -R /mnt 2>/dev/null || true
reboot
