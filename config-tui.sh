#!/bin/bash
# ==========================================================================
# ARCH LINUX INSTALLER - Interface TUI (Text User Interface)
# Version graphique avec dialog/whiptail
# ==========================================================================

set -euo pipefail
IFS=$'\n\t'

# --- Détection de l'outil de dialogue ---
if command -v dialog &>/dev/null; then
    DIALOG="dialog"
elif command -v whiptail &>/dev/null; then
    DIALOG="whiptail"
else
    echo "Installation de dialog..."
    pacman -Sy --noconfirm dialog 2>/dev/null || {
        echo "ERREUR: Impossible d'installer dialog"
        exit 1
    }
    DIALOG="dialog"
fi

# --- Variables globales ---
DIALOG_HEIGHT=20
DIALOG_WIDTH=70
BACKTITLE="Arch Linux Installer Pro - TUI Edition"

# Temporary file for dialog output
TEMP_FILE=$(mktemp)
trap 'rm -f $TEMP_FILE' EXIT ERR

# Configuration variables
USERNAME=""
VMNAME=""
PASS=""
DISK=""
DISK_SIZE_G=0
INSTALL_DOCKER="Non"
INSTALL_NVM="Non"
DE_CHOICE=""
DE_NAME=""
BROWSER=""
BROWSER_NAME=""

# --- Fonctions utilitaires ---

show_msgbox() {
    local title="$1"
    local message="$2"
    $DIALOG --backtitle "$BACKTITLE" --title "$title" --msgbox "$message" 10 60
}

show_infobox() {
    local title="$1"
    local message="$2"
    $DIALOG --backtitle "$BACKTITLE" --title "$title" --infobox "$message" 8 50
    sleep 2
}

show_yesno() {
    local title="$1"
    local question="$2"
    $DIALOG --backtitle "$BACKTITLE" --title "$title" --yesno "$question" 10 60
}

get_input() {
    local title="$1"
    local prompt="$2"
    local default="$3"
    $DIALOG --backtitle "$BACKTITLE" --title "$title" --inputbox "$prompt" 10 60 "$default" 2>$TEMP_FILE
    cat $TEMP_FILE
}

get_password() {
    local title="$1"
    local prompt="$2"
    $DIALOG --backtitle "$BACKTITLE" --title "$title" --passwordbox "$prompt" 10 60 2>$TEMP_FILE
    cat $TEMP_FILE
}

show_menu() {
    local title="$1"
    shift
    $DIALOG --backtitle "$BACKTITLE" --title "$title" --menu "Sélectionnez une option:" $DIALOG_HEIGHT $DIALOG_WIDTH 10 "$@" 2>$TEMP_FILE
    cat $TEMP_FILE
}

show_checklist() {
    local title="$1"
    shift
    $DIALOG --backtitle "$BACKTITLE" --title "$title" --checklist "Sélectionnez (Espace pour cocher):" $DIALOG_HEIGHT $DIALOG_WIDTH 10 "$@" 2>$TEMP_FILE
    cat $TEMP_FILE
}

show_gauge() {
    local title="$1"
    local message="$2"
    $DIALOG --backtitle "$BACKTITLE" --title "$title" --gauge "$message" 8 60
}

# Conversion de taille
size_to_bytes() {
    local size="$1"
    local num unit
    
    if [[ "$size" =~ ^[0-9]+$ ]]; then
        echo "$size"
        return
    fi
    
    num=$(echo "$size" | sed 's/[^0-9.]//g')
    unit=$(echo "$size" | sed 's/[0-9.]//g' | tr '[:lower:]' '[:upper:]')
    
    if [ -z "$unit" ]; then
        echo "${num%.*}"
        return
    fi
    
    case "$unit" in
        K|KB|KIB) echo "$num * 1024" | bc | cut -d. -f1 ;;
        M|MB|MIB) echo "$num * 1024 * 1024" | bc | cut -d. -f1 ;;
        G|GB|GIB) echo "$num * 1024 * 1024 * 1024" | bc | cut -d. -f1 ;;
        T|TB|TIB) echo "$num * 1024 * 1024 * 1024 * 1024" | bc | cut -d. -f1 ;;
        *) echo "${num%.*}" ;;
    esac
}

# --- Écran de bienvenue ---
show_welcome() {
    $DIALOG --backtitle "$BACKTITLE" --title "Bienvenue" --msgbox "\
╔════════════════════════════════════════════════════╗
║   ARCH LINUX INSTALLER PRO - TUI EDITION          ║
║                                                    ║
║   Installation assistée d'Arch Linux              ║
║   avec interface graphique interactive            ║
║                                                    ║
║   Version 2.0 - By MIDO                           ║
╚════════════════════════════════════════════════════╝

Cet installateur va vous guider à travers :
• Configuration du système
• Partitionnement du disque
• Choix de l'environnement graphique
• Installation des logiciels

Appuyez sur OK pour continuer..." 18 60
}

# --- Configuration réseau et dépôts ---
configure_system() {
    show_infobox "Préparation" "Synchronisation de l'horloge système..."
    timedatectl set-ntp true 2>/dev/null || true
    
    show_infobox "Préparation" "Configuration des dépôts Arch Linux..."
    
    # Activer les dépôts
    sed -i '/^\[core\]/,/^Include/ s/^#//' /etc/pacman.conf 2>/dev/null || true
    sed -i '/^\[extra\]/,/^Include/ s/^#//' /etc/pacman.conf 2>/dev/null || true
    
    if ! grep -q '\[extra\]' /etc/pacman.conf; then
        cat >> /etc/pacman.conf <<'EOF'

[extra]
Include = /etc/pacman.d/mirrorlist
EOF
    fi
    
    # Optimiser les miroirs si reflector est disponible
    if command -v reflector &>/dev/null; then
        show_infobox "Préparation" "Optimisation des miroirs (cela peut prendre 1-2 minutes)..."
        reflector --country France,Germany,Belgium --latest 10 --protocol https --sort rate --save /etc/pacman.d/mirrorlist 2>/dev/null || true
    fi
    
    # Synchroniser
    (
        echo "10" ; sleep 0.5
        pacman -Sy --noconfirm 2>&1 | grep -v "warning: database" >/dev/null
        echo "50" ; sleep 0.5
        echo "100"
    ) | show_gauge "Synchronisation" "Synchronisation des bases de données pacman..."
    
    # Vérifier l'accès aux dépôts
    if ! pacman -Si base >/dev/null 2>&1; then
        show_msgbox "ERREUR" "Les dépôts ne sont pas accessibles!\n\nVérifiez votre connexion internet."
        exit 1
    fi
}

# --- Configuration de base ---
configure_basic() {
    # Nom d'utilisateur
    while true; do
        USERNAME=$(get_input "Configuration" "Nom d'utilisateur:" "user")
        [ -n "$USERNAME" ] && break
        show_msgbox "Erreur" "Le nom d'utilisateur ne peut pas être vide"
    done
    
    # Nom de la machine
    while true; do
        VMNAME=$(get_input "Configuration" "Nom de la machine (hostname):" "arch-vm")
        [ -n "$VMNAME" ] && break
        show_msgbox "Erreur" "Le nom de la machine ne peut pas être vide"
    done
    
    # Mot de passe
    while true; do
        PASS=$(get_password "Configuration" "Mot de passe (root et utilisateur):")
        [ -n "$PASS" ] && break
        show_msgbox "Erreur" "Le mot de passe ne peut pas être vide"
    done
}

# --- Sélection du disque ---
select_disk() {
    # Récupérer les disques
    local disks_json=$(lsblk -J -d -o NAME,SIZE,TYPE,MODEL 2>/dev/null)
    
    declare -a disk_names disk_sizes disk_models
    
    # Parser le JSON
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
        
        if [[ "$line" =~ \} ]] && [[ "$type" == "disk" ]] && [[ -n "$name" ]]; then
            disk_names+=("$name")
            disk_sizes+=("$size")
            disk_models+=("${model:-N/A}")
            name="" size="" type="" model=""
        fi
    done <<< "$disks_json"
    
    if [ ${#disk_names[@]} -eq 0 ]; then
        show_msgbox "ERREUR" "Aucun disque détecté!"
        exit 1
    fi
    
    # Créer le menu
    local menu_items=()
    for i in "${!disk_names[@]}"; do
        menu_items+=("/dev/${disk_names[$i]}" "${disk_sizes[$i]} - ${disk_models[$i]}")
    done
    
    DISK=$(show_menu "Sélection du disque" "${menu_items[@]}")
    
    if [ -z "$DISK" ]; then
        show_msgbox "Erreur" "Aucun disque sélectionné"
        exit 1
    fi
    
    # Calculer la taille
    local disk_size_str=$(lsblk -d -n -o SIZE "$DISK" 2>/dev/null)
    local disk_size_bytes=$(size_to_bytes "$disk_size_str")
    DISK_SIZE_G=$(echo "$disk_size_bytes / 1024 / 1024 / 1024" | bc)
}

# --- Options supplémentaires ---
select_options() {
    local selected=$(show_checklist "Options d'installation" \
        "docker" "Docker + Docker Compose" off \
        "nvm" "NVM (Node Version Manager v0.40.4)" off)
    
    [[ "$selected" =~ docker ]] && INSTALL_DOCKER="Oui"
    [[ "$selected" =~ nvm ]] && INSTALL_NVM="Oui"
}

# --- Environnement graphique ---
select_desktop() {
    DE_CHOICE=$(show_menu "Environnement graphique" \
        "1" "GNOME (moderne, complet)" \
        "2" "KDE Plasma (personnalisable)" \
        "3" "XFCE (léger, classique)" \
        "4" "Aucun (serveur/minimal)")
    
    case "$DE_CHOICE" in
        1) DE_NAME="GNOME" ;;
        2) DE_NAME="KDE Plasma" ;;
        3) DE_NAME="XFCE" ;;
        4) DE_NAME="Aucun" ;;
    esac
}

# --- Navigateur ---
select_browser() {
    if [ "$DE_CHOICE" != "4" ]; then
        local browser_choice=$(show_menu "Navigateur Web" \
            "1" "Firefox (79 MB - Recommandé)" \
            "2" "Chromium (119 MB)" \
            "3" "Les deux navigateurs" \
            "4" "Aucun navigateur")
        
        case "$browser_choice" in
            1) BROWSER="firefox"; BROWSER_NAME="Firefox" ;;
            2) BROWSER="chromium"; BROWSER_NAME="Chromium" ;;
            3) BROWSER="firefox chromium"; BROWSER_NAME="Firefox + Chromium" ;;
            4) BROWSER=""; BROWSER_NAME="Aucun" ;;
        esac
    fi
}

# --- Récapitulatif ---
show_summary() {
    local summary="Configuration de l'installation:

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Système:
  • Utilisateur:     $USERNAME
  • Hostname:        $VMNAME
  • Disque:          $DISK ($DISK_SIZE_G GiB)

Logiciels:
  • Desktop:         $DE_NAME
  • Navigateur:      ${BROWSER_NAME:-Aucun}
  • Docker:          $INSTALL_DOCKER
  • NVM:             $INSTALL_NVM

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  ATTENTION: Le disque $DISK sera complètement effacé!

Voulez-vous continuer?"

    if ! show_yesno "Confirmation" "$summary"; then
        show_msgbox "Annulation" "Installation annulée par l'utilisateur"
        exit 0
    fi
}

# --- Partitionnement ---
partition_disk() {
    show_infobox "Partitionnement" "Nettoyage du disque $DISK..."
    
    # Démontage
    for mount_point in $(mount | grep "^$DISK" | awk '{print $3}'); do
        umount -R "$mount_point" 2>/dev/null || true
    done
    swapoff "${DISK}"* 2>/dev/null || true
    swapoff -a 2>/dev/null || true
    fuser -km "$DISK" 2>/dev/null || true
    sleep 2
    
    show_infobox "Partitionnement" "Création de la table de partitions..."
    
    # Détection UEFI/BIOS
    if [ -d /sys/firmware/efi ]; then
        BOOT_MODE="UEFI"
    else
        BOOT_MODE="BIOS"
    fi
    
    # Partitionnement selon la taille
    if [ "$DISK_SIZE_G" -lt 20 ]; then
        SCHEME="small"
    elif [ "$DISK_SIZE_G" -lt 60 ]; then
        SCHEME="medium"
    else
        SCHEME="large"
    fi
    
    if [ "$BOOT_MODE" = "UEFI" ]; then
        wipefs -af "$DISK" 2>/dev/null || true
        dd if=/dev/zero of="$DISK" bs=512 count=1 conv=notrunc 2>/dev/null || true
        sgdisk --zap-all "$DISK" 2>/dev/null || true
        sgdisk --clear "$DISK" 2>/dev/null || true
        
        case "$SCHEME" in
            small)
                sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
                sgdisk -n 2:0:0 -t 2:8300 -c 2:"ROOT" "$DISK"
                ;;
            medium)
                sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
                sgdisk -n 2:0:+2G -t 2:8200 -c 2:"SWAP" "$DISK"
                sgdisk -n 3:0:0 -t 3:8300 -c 3:"ROOT" "$DISK"
                ;;
            large)
                sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI" "$DISK"
                sgdisk -n 2:0:+4G -t 2:8200 -c 2:"SWAP" "$DISK"
                sgdisk -n 3:0:0 -t 3:8300 -c 3:"ROOT" "$DISK"
                ;;
        esac
        
        partprobe "$DISK" 2>/dev/null || true
        udevadm settle 2>/dev/null || true
        sleep 3
        blockdev --rereadpt "$DISK" 2>/dev/null || true
        sleep 1
        
        P_EFI="${DISK}1"
        if [ "$SCHEME" = "small" ]; then
            P_ROOT="${DISK}2"
            USE_SWAPFILE=true
            SWAP_SIZE_MB=2048
        else
            P_SWAP="${DISK}2"
            P_ROOT="${DISK}3"
            USE_SWAPFILE=false
        fi
        
        [[ "$DISK" =~ nvme ]] && {
            P_EFI="${DISK}p1"
            [ "$SCHEME" = "small" ] && P_ROOT="${DISK}p2" || { P_SWAP="${DISK}p2"; P_ROOT="${DISK}p3"; }
        }
    else
        wipefs -af "$DISK" 2>/dev/null || true
        dd if=/dev/zero of="$DISK" bs=512 count=1 conv=notrunc 2>/dev/null || true
        parted -s "$DISK" mklabel msdos
        
        case "$SCHEME" in
            small)
                parted -s "$DISK" mkpart primary ext4 1MiB 100%
                P_ROOT="${DISK}1"
                USE_SWAPFILE=true
                SWAP_SIZE_MB=2048
                ;;
            medium)
                parted -s "$DISK" mkpart primary linux-swap 1MiB 2GiB
                parted -s "$DISK" mkpart primary ext4 2GiB 100%
                P_SWAP="${DISK}1"
                P_ROOT="${DISK}2"
                USE_SWAPFILE=false
                ;;
            large)
                parted -s "$DISK" mkpart primary linux-swap 1MiB 4GiB
                parted -s "$DISK" mkpart primary ext4 4GiB 100%
                P_SWAP="${DISK}1"
                P_ROOT="${DISK}2"
                USE_SWAPFILE=false
                ;;
        esac
        
        partprobe "$DISK" 2>/dev/null || true
        udevadm settle 2>/dev/null || true
        sleep 3
        
        [[ "$DISK" =~ nvme ]] && {
            [ "$SCHEME" = "small" ] && P_ROOT="${DISK}p1" || { P_SWAP="${DISK}p1"; P_ROOT="${DISK}p2"; }
        }
    fi
}

# --- Formatage ---
format_partitions() {
    (
        echo "10"
        if [ -n "${P_SWAP:-}" ]; then
            mkswap "$P_SWAP" >/dev/null 2>&1
            swapon "$P_SWAP"
        fi
        echo "30"
        
        mkfs.ext4 -F "$P_ROOT" >/dev/null 2>&1
        mount "$P_ROOT" /mnt
        echo "60"
        
        if [ "$BOOT_MODE" = "UEFI" ] && [ -n "${P_EFI:-}" ]; then
            mkfs.fat -F32 "$P_EFI" >/dev/null 2>&1
            mkdir -p /mnt/boot/efi
            mount "$P_EFI" /mnt/boot/efi
        fi
        echo "100"
    ) | show_gauge "Formatage" "Formatage des partitions..."
}

# --- Installation des paquets ---
install_packages() {
    # Préparer la liste des paquets
    local pkgs=(base linux linux-firmware base-devel networkmanager sudo vim nano man-db man-pages bash-completion)
    
    # VM tools
    if systemd-detect-virt -q; then
        local virt_type=$(systemd-detect-virt)
        case "$virt_type" in
            kvm|qemu) pkgs+=(qemu-guest-agent) ;;
            vmware) pkgs+=(open-vm-tools) ;;
            oracle) pkgs+=(virtualbox-guest-utils) ;;
        esac
    fi
    
    # Desktop environment
    local de_packages=""
    if [ "$DE_CHOICE" != "4" ]; then
        pkgs+=(xorg-server)
        case "$DE_CHOICE" in
            1) de_packages="gdm" ;;
            2) de_packages="sddm plasma-desktop konsole dolphin" ;;
            3) de_packages="lightdm lightdm-gtk-greeter xfce4-session xfce4-panel thunar xfce4-terminal" ;;
        esac
        read -r -a de_array <<< "$de_packages"
        pkgs+=("${de_array[@]}")
        
        # Navigateur
        if [ -n "$BROWSER" ]; then
            read -r -a browser_array <<< "$BROWSER"
            pkgs+=("${browser_array[@]}")
        fi
    fi
    
    # Docker
    [[ "$INSTALL_DOCKER" == "Oui" ]] && pkgs+=(docker docker-compose)
    
    # Installation avec barre de progression
    (
        echo "0" ; sleep 0.5
        echo "# Installation des paquets de base..."
        pacstrap -K /mnt "${pkgs[@]}" 2>&1 | while read -r line; do
            echo "#$line"
        done
        echo "50"
        
        # Groupe complet DE si demandé
        if [ "$DE_CHOICE" == "1" ] || [ "$DE_CHOICE" == "2" ]; then
            if show_yesno "Installation complète" "Installer le groupe complet $DE_NAME?\n(Plus de paquets mais plus complet)"; then
                case "$DE_CHOICE" in
                    1) yes "" | pacstrap /mnt gnome 2>&1 ;;
                    2) yes "" | pacstrap /mnt plasma 2>&1 ;;
                esac
            fi
        fi
        
        echo "100"
    ) | $DIALOG --backtitle "$BACKTITLE" --title "Installation" --gauge "Installation en cours..." 10 70 0
}

# --- Configuration du système ---
configure_installed_system() {
    show_infobox "Configuration" "Configuration du système installé..."
    
    # fstab
    genfstab -U /mnt >> /mnt/etc/fstab
    
    # Créer le script de configuration
    cat > /mnt/tmp/setup.sh <<EOSCRIPT
#!/bin/bash
set -e

# Timezone et locale
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc

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
[[ "$INSTALL_DOCKER" == "Oui" ]] && usermod -aG docker "$USERNAME" 2>/dev/null || true

# Sudo
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# NVM
if [[ "$INSTALL_NVM" == "Oui" ]]; then
    sudo -u "$USERNAME" bash -c 'curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash'
fi

# Swapfile
if [ "${USE_SWAPFILE:-false}" = true ]; then
    dd if=/dev/zero of=/swapfile bs=1M count=${SWAP_SIZE_MB} status=progress
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

case "$DE_CHOICE" in
    1) systemctl enable gdm ;;
    2) systemctl enable sddm ;;
    3) systemctl enable lightdm ;;
esac

systemctl list-unit-files | grep -q qemu-guest-agent && systemctl enable qemu-guest-agent || true
systemctl list-unit-files | grep -q vmtoolsd && systemctl enable vmtoolsd || true
systemctl list-unit-files | grep -q vboxservice && systemctl enable vboxservice || true

[[ "$INSTALL_DOCKER" == "Oui" ]] && systemctl enable docker

rm -f /tmp/setup.sh
EOSCRIPT

    chmod +x /mnt/tmp/setup.sh
    
    (
        echo "30"
        arch-chroot /mnt /tmp/setup.sh 2>&1 | while read -r line; do
            echo "#$line"
        done
        echo "100"
    ) | show_gauge "Configuration" "Configuration du système..."
}

# --- Fonction principale ---
main() {
    # Vérifier qu'on est root
    if [ "$EUID" -ne 0 ]; then
        echo "Ce script doit être exécuté en tant que root"
        exit 1
    fi
    
    show_welcome
    configure_system
    configure_basic
    select_disk
    select_options
    select_desktop
    select_browser
    show_summary
    partition_disk
    format_partitions
    install_packages
    configure_installed_system
    
    # Fin
    show_msgbox "Installation terminée!" "\
╔═══════════════════════════════════════════════════╗
║  ✓ INSTALLATION TERMINÉE AVEC SUCCÈS !           ║
╚═══════════════════════════════════════════════════╝

Configuration:
  • Utilisateur: $USERNAME
  • Hostname:    $VMNAME
  • Desktop:     $DE_NAME
  • Navigateur:  ${BROWSER_NAME:-Aucun}

Retirez le média d'installation et redémarrez."
    
    umount -R /mnt 2>/dev/null || true
    
    if show_yesno "Redémarrage" "Voulez-vous redémarrer maintenant?"; then
        reboot
    fi
}

# Lancer l'installation
main "$@"
