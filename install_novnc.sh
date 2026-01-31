#!/bin/bash
# ============================================================================
# noVNC Universal Installer - Linux Edition
# Installation automatique pour toutes les distributions Linux
# Support: Arch, Debian, Ubuntu, Fedora, RHEL, CentOS, AlmaLinux, Rocky, 
#          openSUSE, Alpine, Gentoo, Void, et plus
# ============================================================================

set -e

# ============================================================================
# CONFIGURATION PAR DÉFAUT
# ============================================================================
DEFAULT_PORT=6081
DEFAULT_VNC_DISPLAY=":1"
DEFAULT_VNC_PORT=5901
NOVNC_VERSION="v1.6.0"

# Variables globales
PORT="$DEFAULT_PORT"
VNC_DISPLAY="$DEFAULT_VNC_DISPLAY"
VNC_PORT="$DEFAULT_VNC_PORT"
VNC_PASSWORD=""
SKIP_PASSWORD=false
OS_TYPE=""
OS_VERSION=""
PKG_MANAGER=""
USE_TUI=false
TUI_CMD=""
INSTALL_DIR="$HOME/novnc-setup"

# Couleurs pour output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================================
# FONCTIONS UTILITAIRES
# ============================================================================
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_step() {
    echo -e "\n${CYAN}[+]${NC} ${BOLD}$1${NC}"
}

# ============================================================================
# DÉTECTION DE LA DISTRIBUTION LINUX
# ============================================================================
detect_os() {
    log_step "Détection du système d'exploitation..."
    
    if [[ ! -f /etc/os-release ]]; then
        log_error "Impossible de détecter la distribution Linux"
        log_info "Fichier /etc/os-release non trouvé"
        exit 1
    fi
    
    # Charger les informations OS
    . /etc/os-release
    OS_TYPE="$ID"
    OS_VERSION="$VERSION_ID"
    
    # Déterminer le gestionnaire de paquets
    case "$OS_TYPE" in
        arch|manjaro|endeavouros|artix|garuda|arcolinux)
            PKG_MANAGER="pacman"
            log_success "Distribution Arch détectée: $PRETTY_NAME"
            ;;
        ubuntu|debian|mint|pop|elementary|kali|parrot|deepin|zorin|mx)
            PKG_MANAGER="apt"
            log_success "Distribution Debian/Ubuntu détectée: $PRETTY_NAME"
            ;;
        fedora|nobara)
            PKG_MANAGER="dnf"
            log_success "Distribution Fedora détectée: $PRETTY_NAME"
            ;;
        rhel|centos|rocky|alma|almalinux|ol|oracle)
            PKG_MANAGER="dnf"
            log_success "Distribution RHEL/CentOS détectée: $PRETTY_NAME"
            ;;
        opensuse*|sles|sled)
            PKG_MANAGER="zypper"
            log_success "Distribution openSUSE détectée: $PRETTY_NAME"
            ;;
        alpine)
            PKG_MANAGER="apk"
            log_success "Distribution Alpine détectée: $PRETTY_NAME"
            ;;
        gentoo|funtoo)
            PKG_MANAGER="emerge"
            log_success "Distribution Gentoo détectée: $PRETTY_NAME"
            ;;
        void)
            PKG_MANAGER="xbps"
            log_success "Distribution Void détectée: $PRETTY_NAME"
            ;;
        solus)
            PKG_MANAGER="eopkg"
            log_success "Distribution Solus détectée: $PRETTY_NAME"
            ;;
        nixos)
            PKG_MANAGER="nix"
            log_success "Distribution NixOS détectée: $PRETTY_NAME"
            ;;
        *)
            log_warning "Distribution non reconnue: $PRETTY_NAME"
            log_info "Tentative de détection automatique du gestionnaire de paquets..."
            detect_package_manager_fallback
            ;;
    esac
}

detect_package_manager_fallback() {
    if command -v apt-get &> /dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &> /dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &> /dev/null; then
        PKG_MANAGER="yum"
    elif command -v pacman &> /dev/null; then
        PKG_MANAGER="pacman"
    elif command -v zypper &> /dev/null; then
        PKG_MANAGER="zypper"
    elif command -v apk &> /dev/null; then
        PKG_MANAGER="apk"
    elif command -v emerge &> /dev/null; then
        PKG_MANAGER="emerge"
    elif command -v xbps-install &> /dev/null; then
        PKG_MANAGER="xbps"
    else
        log_error "Aucun gestionnaire de paquets supporté détecté"
        exit 1
    fi
    log_success "Gestionnaire détecté: $PKG_MANAGER"
}

# ============================================================================
# VÉRIFICATION TUI (Dialog ou Whiptail)
# ============================================================================
check_tui() {
    if command -v dialog &> /dev/null; then
        USE_TUI=true
        TUI_CMD="dialog"
        log_success "Interface TUI disponible: dialog"
    elif command -v whiptail &> /dev/null; then
        USE_TUI=true
        TUI_CMD="whiptail"
        log_success "Interface TUI disponible: whiptail"
    else
        USE_TUI=false
        log_info "Interface TUI non disponible, utilisation du mode CLI"
    fi
}

# ============================================================================
# INSTALLATION DE L'INTERFACE TUI SI NÉCESSAIRE
# ============================================================================
install_tui() {
    log_step "Installation de l'interface TUI (dialog)..."
    
    case "$PKG_MANAGER" in
        pacman)
            sudo pacman -S --needed --noconfirm dialog
            ;;
        apt)
            sudo apt-get update -qq
            sudo apt-get install -y -qq dialog
            ;;
        dnf|yum)
            sudo $PKG_MANAGER install -y -q dialog
            ;;
        zypper)
            sudo zypper install -y dialog
            ;;
        apk)
            sudo apk add --no-cache dialog
            ;;
        emerge)
            sudo emerge --quiet dev-util/dialog
            ;;
        xbps)
            sudo xbps-install -y dialog
            ;;
        eopkg)
            sudo eopkg install -y dialog
            ;;
    esac
    
    if command -v dialog &> /dev/null; then
        USE_TUI=true
        TUI_CMD="dialog"
        log_success "Dialog installé avec succès"
    fi
}

# ============================================================================
# INTERFACE TUI - ÉCRAN D'ACCUEIL
# ============================================================================
tui_welcome() {
    $TUI_CMD --title "noVNC Universal Installer" \
        --msgbox "╔═══════════════════════════════════════════════╗\n║  Bienvenue dans l'installateur noVNC !       ║\n╚═══════════════════════════════════════════════╝\n\nCe script va installer et configurer:\n\n  • Serveur VNC (TigerVNC/TightVNC/x11vnc)\n  • noVNC (Interface web VNC)\n  • websockify (Proxy WebSocket)\n  • Interface web accessible via navigateur\n\nSystème détecté:\n  Distribution: $OS_TYPE\n  Gestionnaire: $PKG_MANAGER\n  Version: $OS_VERSION" 20 70
}

# ============================================================================
# INTERFACE TUI - CONFIGURATION
# ============================================================================
tui_configure() {
    local temp_file=$(mktemp)
    
    # Configuration du port noVNC
    $TUI_CMD --title "Configuration - Port noVNC" \
        --inputbox "Entrez le port pour l'interface web noVNC:\n\n(Port sur lequel vous accéderez à http://localhost:PORT)" 12 70 "$DEFAULT_PORT" 2>"$temp_file"
    
    if [[ $? -eq 0 ]]; then
        local input=$(cat "$temp_file")
        if [[ -n "$input" ]] && [[ "$input" =~ ^[0-9]+$ ]]; then
            PORT="$input"
        fi
    fi
    
    # Configuration du display VNC
    $TUI_CMD --title "Configuration - Display VNC" \
        --inputbox "Entrez le display VNC (format :N):\n\nExemples: :1, :2, :99\nLe port VNC sera automatiquement 5900+N" 12 70 "$DEFAULT_VNC_DISPLAY" 2>"$temp_file"
    
    if [[ $? -eq 0 ]]; then
        local input=$(cat "$temp_file")
        if [[ -n "$input" ]] && [[ "$input" =~ ^:[0-9]+$ ]]; then
            VNC_DISPLAY="$input"
            local display_num="${VNC_DISPLAY/:/}"
            VNC_PORT=$((5900 + display_num))
        fi
    fi
    
    rm -f "$temp_file"
    
    # Confirmation de la configuration
    $TUI_CMD --title "Confirmation" \
        --yesno "Configuration choisie:\n\n  Port noVNC:    $PORT\n  Display VNC:   $VNC_DISPLAY\n  Port VNC:      $VNC_PORT\n\nContinuer avec cette configuration?" 13 60
    
    if [[ $? -ne 0 ]]; then
        tui_configure  # Recommencer la configuration
    fi
}

# ============================================================================
# INTERFACE TUI - BARRE DE PROGRESSION
# ============================================================================
tui_progress() {
    local percent="$1"
    local message="$2"
    echo "$percent" | $TUI_CMD --title "Installation en cours" --gauge "$message" 8 70 0
}

# ============================================================================
# INTERFACE CLI - BANNIÈRE
# ============================================================================
cli_welcome() {
    clear
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║           noVNC Universal Installer v2.0                      ║
║              Linux All-Distributions Edition                  ║
║                                                               ║
║  Installation automatique de noVNC pour accès VNC web        ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo ""
    log_info "Système détecté: ${CYAN}$OS_TYPE${NC} (${YELLOW}$PKG_MANAGER${NC})"
    log_info "Version: ${CYAN}${OS_VERSION:-N/A}${NC}"
    echo ""
}

# ============================================================================
# INTERFACE CLI - CONFIGURATION
# ============================================================================
cli_configure() {
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}         CONFIGURATION${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo ""
    
    read -p "$(echo -e ${BLUE}Port pour l\'interface web noVNC${NC} [$DEFAULT_PORT]: )" input
    if [[ -n "$input" ]] && [[ "$input" =~ ^[0-9]+$ ]]; then
        PORT="$input"
    fi
    
    read -p "$(echo -e ${BLUE}Display VNC${NC} [$DEFAULT_VNC_DISPLAY]: )" input
    if [[ -n "$input" ]] && [[ "$input" =~ ^:[0-9]+$ ]]; then
        VNC_DISPLAY="$input"
    fi
    
    # Calculer le port VNC
    local display_num="${VNC_DISPLAY/:/}"
    VNC_PORT=$((5900 + display_num))
    
    echo ""
    echo -e "${GREEN}Configuration choisie:${NC}"
    echo -e "  ${YELLOW}→${NC} Port noVNC:  ${CYAN}$PORT${NC}"
    echo -e "  ${YELLOW}→${NC} Display VNC: ${CYAN}$VNC_DISPLAY${NC}"
    echo -e "  ${YELLOW}→${NC} Port VNC:    ${CYAN}$VNC_PORT${NC}"
    echo ""
    
    read -p "$(echo -e ${BLUE}Continuer avec cette configuration?${NC} [O/n]: )" confirm
    if [[ "$confirm" =~ ^[Nn] ]]; then
        cli_configure  # Recommencer
    fi
}

# ============================================================================
# INSTALLATION DES DÉPENDANCES
# ============================================================================
install_dependencies() {
    log_step "Installation des dépendances système..."
    
    case "$PKG_MANAGER" in
        pacman)
            log_info "Mise à jour du système Arch..."
            sudo pacman -Syu --needed --noconfirm git python tigervnc python-pipx xorg-server xfce4 xorg-server-xvfb || \
            sudo pacman -S --needed --noconfirm git python tigervnc python-pip xorg-server xfce4 xorg-server-xvfb
            ;;
            
        apt)
            log_info "Mise à jour du cache APT..."
            sudo apt-get update -qq
            log_info "Installation des paquets Debian/Ubuntu..."
            sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
                git python3 python3-pip python3-venv tightvncserver \
                x11vnc xfce4 xfce4-goodies dbus-x11 || \
            sudo apt-get install -y git python3 python3-pip tightvncserver x11vnc
            # Installation de pipx
            python3 -m pip install --user pipx 2>/dev/null || true
            ;;
            
        dnf)
            log_info "Installation des paquets Fedora/RHEL..."
            sudo dnf install -y -q git python3 python3-pip tigervnc-server \
                xorg-x11-server-Xorg xfce4-session || \
            sudo dnf install -y git python3 python3-pip tigervnc-server
            python3 -m pip install --user pipx 2>/dev/null || true
            ;;
            
        yum)
            log_info "Installation des paquets CentOS/RHEL (yum)..."
            sudo yum install -y -q git python3 python3-pip tigervnc-server \
                xorg-x11-server-Xorg || \
            sudo yum install -y git python3 tigervnc-server
            python3 -m pip install --user pipx 2>/dev/null || true
            ;;
            
        zypper)
            log_info "Installation des paquets openSUSE..."
            sudo zypper refresh
            sudo zypper install -y git python3 python3-pip tigervnc xorg-x11-server || \
            sudo zypper install -y git python3 tigervnc
            python3 -m pip install --user pipx 2>/dev/null || true
            ;;
            
        apk)
            log_info "Installation des paquets Alpine..."
            sudo apk add --no-cache git python3 py3-pip x11vnc xvfb xfce4 || \
            sudo apk add --no-cache git python3 x11vnc
            python3 -m pip install --user pipx --break-system-packages 2>/dev/null || true
            ;;
            
        emerge)
            log_info "Installation des paquets Gentoo..."
            sudo emerge --quiet --ask=n net-misc/tigervnc dev-python/pip dev-vcs/git || \
            sudo emerge net-misc/tigervnc dev-python/pip dev-vcs/git
            python3 -m pip install --user pipx 2>/dev/null || true
            ;;
            
        xbps)
            log_info "Installation des paquets Void Linux..."
            sudo xbps-install -Syu
            sudo xbps-install -y git python3 python3-pip tigervnc xorg-server xfce4 || \
            sudo xbps-install -y git python3 tigervnc
            python3 -m pip install --user pipx 2>/dev/null || true
            ;;
            
        eopkg)
            log_info "Installation des paquets Solus..."
            sudo eopkg install -y git python3 python3-pip tigervnc || \
            sudo eopkg install -y git python3
            python3 -m pip install --user pipx 2>/dev/null || true
            ;;
            
        nix)
            log_info "Installation des paquets NixOS..."
            nix-env -iA nixpkgs.git nixpkgs.python3 nixpkgs.tigervnc || \
            nix-env -i git python3
            python3 -m pip install --user pipx 2>/dev/null || true
            ;;
            
        *)
            log_error "Gestionnaire de paquets non supporté: $PKG_MANAGER"
            log_warning "Veuillez installer manuellement: git, python3, tigervnc/x11vnc"
            exit 1
            ;;
    esac
    
    log_success "Dépendances système installées"
}

# ============================================================================
# INSTALLATION DE WEBSOCKIFY
# ============================================================================
install_websockify() {
    log_step "Installation de websockify..."
    
    # S'assurer que le PATH inclut les binaires locaux
    export PATH="$PATH:$HOME/.local/bin"
    
    # Forcer les variables d'environnement utilisateur
    export HOME="$HOME"
    export USER="$USER"
    unset SUDO_USER SUDO_UID SUDO_GID
    
    if command -v pipx &> /dev/null; then
        log_info "Installation via pipx..."
        # Tenter avec pipx
        if ! pipx install --force websockify 2>&1; then
            log_warning "Échec de pipx, tentative avec pip..."
            python3 -m pip install --user websockify --break-system-packages 2>/dev/null || \
            python3 -m pip install --user websockify 2>/dev/null || {
                log_error "Impossible d'installer websockify"
                exit 1
            }
        fi
    else
        log_info "pipx non disponible, installation via pip..."
        python3 -m pip install --user websockify --break-system-packages 2>/dev/null || \
        python3 -m pip install --user websockify 2>/dev/null || {
            log_error "Impossible d'installer websockify"
            exit 1
        }
    fi
    
    # Vérifier que websockify est accessible
    if command -v websockify &> /dev/null || [[ -f "$HOME/.local/bin/websockify" ]]; then
        log_success "websockify installé"
    else
        log_warning "websockify installé mais non trouvé dans PATH"
        log_info "Il sera utilisé depuis $HOME/.local/bin/"
    fi
}

# ============================================================================
# TÉLÉCHARGEMENT DE NOVNC
# ============================================================================
download_novnc() {
    log_step "Téléchargement de noVNC $NOVNC_VERSION..."
    
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    if [[ -d noVNC ]]; then
        log_info "noVNC déjà présent, mise à jour..."
        cd noVNC
        git fetch --quiet
        git checkout --quiet "$NOVNC_VERSION"
        cd ..
    else
        log_info "Clonage du dépôt noVNC..."
        git clone --quiet --branch "$NOVNC_VERSION" --depth 1 https://github.com/novnc/noVNC.git
    fi
    
    log_success "noVNC téléchargé dans $INSTALL_DIR/noVNC"
}

# ============================================================================
# CONFIGURATION DU MOT DE PASSE VNC
# ============================================================================
setup_vnc_password() {
    log_step "Configuration du mot de passe VNC..."
    
    mkdir -p "$HOME/.vnc"
    
    if [[ -f "$HOME/.vnc/passwd" ]]; then
        log_success "Mot de passe VNC existant trouvé"
        return 0
    fi
    
    log_info "Configuration du mot de passe VNC"
    echo ""
    
    # Si mot de passe fourni en argument
    if [[ -n "$VNC_PASSWORD" ]]; then
        log_info "Utilisation du mot de passe fourni en argument"
        echo -e "$VNC_PASSWORD\n$VNC_PASSWORD\nn" | vncpasswd 2>/dev/null || {
            log_error "Impossible de définir le mot de passe"
            exit 1
        }
        log_success "Mot de passe VNC configuré"
        return 0
    fi
    
    # Si skip password demandé
    if $SKIP_PASSWORD; then
        log_warning "Mot de passe par défaut: 'novnc123'"
        echo -e "novnc123\nnovnc123\nn" | vncpasswd 2>/dev/null
        log_warning "CHANGEZ-LE avec: vncpasswd"
        log_success "Mot de passe VNC configuré"
        return 0
    fi
    
    # Mode interactif : demander dans TUI ou CLI
    if $USE_TUI; then
        # Avec TUI, on demande le mot de passe
        local temp_file=$(mktemp)
        
        $TUI_CMD --title "Mot de passe VNC" \
            --passwordbox "Entrez un mot de passe VNC (8 caractères minimum):\n\nCe mot de passe sera requis pour se connecter au serveur VNC." 12 60 2>"$temp_file"
        
        if [[ $? -eq 0 ]]; then
            local pass1=$(cat "$temp_file")
            
            $TUI_CMD --title "Confirmation" \
                --passwordbox "Confirmez le mot de passe VNC:" 10 60 2>"$temp_file"
            
            if [[ $? -eq 0 ]]; then
                local pass2=$(cat "$temp_file")
                
                if [[ "$pass1" == "$pass2" ]] && [[ ${#pass1} -ge 6 ]]; then
                    echo -e "$pass1\n$pass1\nn" | vncpasswd 2>/dev/null
                    rm -f "$temp_file"
                    log_success "Mot de passe VNC configuré"
                    return 0
                else
                    rm -f "$temp_file"
                    log_error "Les mots de passe ne correspondent pas ou sont trop courts"
                    log_warning "Utilisation du mot de passe par défaut: 'novnc123'"
                    echo -e "novnc123\nnovnc123\nn" | vncpasswd 2>/dev/null
                    return 0
                fi
            fi
        fi
        rm -f "$temp_file"
    fi
    
    # Mode CLI ou échec TUI : vérifier si terminal interactif
    if [[ -t 0 ]] && [[ -t 1 ]]; then
        # Terminal interactif : utiliser vncpasswd directement
        log_info "Veuillez définir un mot de passe VNC:"
        echo ""
        
        if vncpasswd 2>&1; then
            log_success "Mot de passe VNC configuré"
            return 0
        else
            log_warning "Erreur lors de la saisie, utilisation du mot de passe par défaut"
            echo -e "novnc123\nnovnc123\nn" | vncpasswd 2>/dev/null
            log_warning "Mot de passe par défaut: 'novnc123' - Changez-le avec: vncpasswd"
            return 0
        fi
    else
        # Mode non-interactif (pipe, script, etc.)
        log_warning "Mode non-interactif détecté"
        log_info "Utilisation du mot de passe par défaut: 'novnc123'"
        echo -e "novnc123\nnovnc123\nn" | vncpasswd 2>/dev/null
        log_warning "CHANGEZ-LE avec: vncpasswd"
        log_success "Mot de passe VNC configuré"
        return 0
    fi
}

# ============================================================================
# CRÉATION DU FICHIER XSTARTUP
# ============================================================================
create_xstartup() {
    log_step "Création du fichier de démarrage X..."
    
    mkdir -p "$HOME/.vnc"
    
    # Détecter l'environnement de bureau disponible
    local de_cmd=""
    if command -v startxfce4 &> /dev/null; then
        de_cmd="startxfce4"
        log_info "XFCE4 détecté"
    elif command -v startkde &> /dev/null; then
        de_cmd="startkde"
        log_info "KDE détecté"
    elif command -v gnome-session &> /dev/null; then
        de_cmd="gnome-session"
        log_info "GNOME détecté"
    elif command -v mate-session &> /dev/null; then
        de_cmd="mate-session"
        log_info "MATE détecté"
    elif command -v startlxde &> /dev/null; then
        de_cmd="startlxde"
        log_info "LXDE détecté"
    else
        de_cmd="xterm"
        log_warning "Aucun DE détecté, utilisation de xterm"
    fi
    
    cat > "$HOME/.vnc/xstartup" << XSTARTUP
#!/bin/bash
# xstartup généré par noVNC Universal Installer

unset SESSION_MANAGER
unset DBUS_SESSION_BUS_ADDRESS

# Démarrage de dbus si disponible
if command -v dbus-launch &> /dev/null; then
    eval \$(dbus-launch --sh-syntax --exit-with-session)
fi

# Définir l'environnement
export XKL_XMODMAP_DISABLE=1
export XDG_CURRENT_DESKTOP=XFCE
export XDG_SESSION_TYPE=x11

# Lancer l'environnement de bureau
exec $de_cmd &
XSTARTUP
    
    chmod +x "$HOME/.vnc/xstartup"
    log_success "Fichier xstartup créé avec $de_cmd"
}

# ============================================================================
# DÉMARRAGE DU SERVEUR VNC
# ============================================================================
start_vnc_server() {
    log_step "Démarrage du serveur VNC (Display $VNC_DISPLAY)..."
    
    # Vérifier si un serveur VNC tourne déjà
    if pgrep -f "Xvnc $VNC_DISPLAY" >/dev/null 2>&1; then
        log_warning "Un serveur VNC tourne déjà sur $VNC_DISPLAY"
        
        # En mode auto, redémarrer automatiquement
        if $AUTO_MODE; then
            log_info "Mode automatique : redémarrage du serveur existant..."
            vncserver -kill "$VNC_DISPLAY" 2>/dev/null || true
            sleep 2
        else
            # Sinon demander seulement si terminal interactif
            if [[ -t 0 ]] && [[ -t 1 ]]; then
                read -p "$(echo -e ${YELLOW}Voulez-vous le redémarrer?${NC} [o/N]: )" restart
                if [[ "$restart" =~ ^[Oo]$ ]]; then
                    log_info "Arrêt du serveur existant..."
                    vncserver -kill "$VNC_DISPLAY" 2>/dev/null || true
                    sleep 2
                else
                    log_info "Utilisation du serveur existant"
                    return 0
                fi
            else
                log_info "Mode non-interactif : utilisation du serveur existant"
                return 0
            fi
        fi
    fi
    
    # Démarrer le serveur VNC
    log_info "Lancement de vncserver..."
    
    # Déterminer la version de vncserver et utiliser la bonne syntaxe
    local vnc_version=$(vncserver --version 2>&1 | head -1)
    
    # TigerVNC 1.13+ utilise une syntaxe différente
    if vncserver -list >/dev/null 2>&1; then
        # Nouvelle syntaxe TigerVNC (1.13+)
        log_info "TigerVNC moderne détecté, utilisation de la nouvelle syntaxe"
        vncserver "$VNC_DISPLAY" -geometry 1920x1080 -depth 24 -localhost no 2>&1 || {
            log_warning "Erreur avec la syntaxe moderne, tentative syntaxe alternative..."
            # Essayer sans le display (TigerVNC 1.16+)
            vncserver -geometry 1920x1080 -depth 24 -localhost no 2>&1 || {
                log_error "Erreur lors du démarrage de vncserver"
                log_info "Tentative avec x11vnc..."
                start_x11vnc_fallback
                return $?
            }
        }
    else
        # Ancienne syntaxe ou autre VNC server
        vncserver "$VNC_DISPLAY" -geometry 1920x1080 -depth 24 2>&1 || {
            log_error "Erreur lors du démarrage de vncserver"
            log_info "Tentative avec x11vnc..."
            start_x11vnc_fallback
            return $?
        }
    fi
    
    # Vérifier que le serveur a bien démarré
    sleep 2
    if pgrep -f "Xvnc" >/dev/null 2>&1; then
        log_success "Serveur VNC démarré sur $VNC_DISPLAY (port $VNC_PORT)"
    else
        log_error "Le serveur VNC ne semble pas avoir démarré"
        log_info "Tentative avec x11vnc..."
        start_x11vnc_fallback
        return $?
    fi
}

# Fonction de fallback pour x11vnc
start_x11vnc_fallback() {
    if command -v x11vnc &> /dev/null; then
        # Démarrer un serveur X virtuel d'abord
        if command -v Xvfb &> /dev/null; then
            log_info "Démarrage de Xvfb..."
            Xvfb "$VNC_DISPLAY" -screen 0 1920x1080x24 &
            sleep 2
        fi
        
        log_info "Démarrage de x11vnc..."
        x11vnc -display "$VNC_DISPLAY" -bg -nopw -listen localhost -xkb -forever 2>/dev/null &
        sleep 2
        
        if pgrep -f "x11vnc" >/dev/null 2>&1; then
            log_success "x11vnc démarré"
            return 0
        else
            log_error "Échec du démarrage de x11vnc"
            return 1
        fi
    else
        log_error "x11vnc non disponible"
        log_error "Impossible de démarrer un serveur VNC"
        log_info "Installez x11vnc ou vérifiez la configuration de TigerVNC"
        return 1
    fi
}

# ============================================================================
# DÉMARRAGE DE NOVNC
# ============================================================================
start_novnc() {
    log_step "Démarrage de noVNC (port $PORT)..."
    
    cd "$INSTALL_DIR/noVNC"
    
    # S'assurer que websockify est dans le PATH
    export PATH="$PATH:$HOME/.local/bin"
    
    # Vérifier si le port est déjà utilisé
    if lsof -i ":$PORT" >/dev/null 2>&1 || netstat -tuln 2>/dev/null | grep -q ":$PORT "; then
        log_warning "Le port $PORT est déjà utilisé"
        local pid=$(lsof -t -i ":$PORT" 2>/dev/null)
        if [[ -n "$pid" ]]; then
            log_info "Processus actuel: PID $pid"
            read -p "$(echo -e ${YELLOW}Voulez-vous arrêter ce processus?${NC} [o/N]: )" kill_proc
            if [[ "$kill_proc" =~ ^[Oo]$ ]]; then
                kill "$pid" 2>/dev/null || sudo kill "$pid"
                sleep 2
            else
                log_error "Impossible de démarrer noVNC sur le port $PORT"
                exit 1
            fi
        fi
    fi
    
    # Démarrer noVNC
    log_info "Lancement du proxy noVNC..."
    
    # Trouver websockify
    local websockify_cmd=""
    if command -v websockify &> /dev/null; then
        websockify_cmd="websockify"
    elif [[ -f "$HOME/.local/bin/websockify" ]]; then
        websockify_cmd="$HOME/.local/bin/websockify"
    elif [[ -f ./utils/novnc_proxy ]]; then
        websockify_cmd="./utils/novnc_proxy"
    else
        log_error "websockify non trouvé"
        exit 1
    fi
    
    # Démarrer en arrière-plan
    if [[ "$websockify_cmd" == "./utils/novnc_proxy" ]]; then
        ./utils/novnc_proxy --vnc localhost:"$VNC_PORT" --listen "$PORT" > /dev/null 2>&1 &
    else
        $websockify_cmd --web . "$PORT" localhost:"$VNC_PORT" > /dev/null 2>&1 &
    fi
    
    local novnc_pid=$!
    sleep 3
    
    # Vérifier que le processus tourne
    if ps -p $novnc_pid > /dev/null 2>&1; then
        # Sauvegarder le PID
        echo "$novnc_pid" > "$INSTALL_DIR/novnc.pid"
        
        log_success "noVNC démarré avec succès!"
        show_success_message "$novnc_pid"
        create_management_scripts "$novnc_pid"
    else
        log_error "Échec du démarrage de noVNC"
        exit 1
    fi
}

# ============================================================================
# AFFICHAGE DU MESSAGE DE SUCCÈS
# ============================================================================
show_success_message() {
    local pid=$1
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                   ✓ Installation réussie !                   ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}🌐 Interface web accessible sur:${NC}"
    echo -e "   ${YELLOW}→${NC} http://localhost:$PORT/vnc.html"
    echo -e "   ${YELLOW}→${NC} http://127.0.0.1:$PORT/vnc.html"
    echo ""
    
    # Obtenir l'IP locale
    local local_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [[ -n "$local_ip" ]]; then
        echo -e "${CYAN}🔗 Accès réseau local:${NC}"
        echo -e "   ${YELLOW}→${NC} http://$local_ip:$PORT/vnc.html"
        echo ""
    fi
    
    echo -e "${CYAN}📡 Informations VNC:${NC}"
    echo -e "   ${YELLOW}→${NC} Display:  $VNC_DISPLAY"
    echo -e "   ${YELLOW}→${NC} Port:     $VNC_PORT"
    echo -e "   ${YELLOW}→${NC} Host:     localhost"
    echo ""
    echo -e "${CYAN}🛠️  Gestion des services:${NC}"
    echo -e "   ${YELLOW}→${NC} Arrêter tout:  $INSTALL_DIR/stop-novnc.sh"
    echo -e "   ${YELLOW}→${NC} Redémarrer:    $INSTALL_DIR/restart-novnc.sh"
    echo -e "   ${YELLOW}→${NC} Statut:        $INSTALL_DIR/status-novnc.sh"
    echo ""
    echo -e "${CYAN}🔐 Connexion:${NC}"
    echo -e "   ${YELLOW}→${NC} Mot de passe: Celui défini lors de vncpasswd"
    echo ""
    echo -e "${CYAN}📝 Processus:${NC}"
    echo -e "   ${YELLOW}→${NC} noVNC PID:  $pid"
    echo -e "   ${YELLOW}→${NC} Répertoire: $INSTALL_DIR"
    echo ""
    
    if $USE_TUI; then
        $TUI_CMD --title "Installation terminée" --msgbox "✓ noVNC est maintenant accessible!\n\nInterface web:\nhttp://localhost:$PORT/vnc.html\n\nScripts de gestion créés dans:\n$INSTALL_DIR/\n\n• stop-novnc.sh\n• restart-novnc.sh\n• status-novnc.sh" 16 70
    fi
}

# ============================================================================
# CRÉATION DES SCRIPTS DE GESTION
# ============================================================================
create_management_scripts() {
    local pid=$1
    
    log_step "Création des scripts de gestion..."
    
    # Script d'arrêt
    cat > "$INSTALL_DIR/stop-novnc.sh" << 'STOPSCRIPT'
#!/bin/bash
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$INSTALL_DIR/config.sh"

echo "Arrêt des services noVNC..."

# Arrêter noVNC
if [[ -f "$INSTALL_DIR/novnc.pid" ]]; then
    PID=$(cat "$INSTALL_DIR/novnc.pid")
    if ps -p "$PID" > /dev/null 2>&1; then
        kill "$PID" 2>/dev/null
        echo "✓ noVNC arrêté (PID: $PID)"
    fi
    rm -f "$INSTALL_DIR/novnc.pid"
fi

# Arrêter VNC
vncserver -kill "$VNC_DISPLAY" 2>/dev/null && echo "✓ VNC arrêté (Display: $VNC_DISPLAY)" || echo "VNC non actif"

echo "Services arrêtés."
STOPSCRIPT
    
    # Script de redémarrage
    cat > "$INSTALL_DIR/restart-novnc.sh" << 'RESTARTSCRIPT'
#!/bin/bash
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$INSTALL_DIR/config.sh"

echo "Redémarrage des services noVNC..."

# Arrêter les services
"$INSTALL_DIR/stop-novnc.sh"
sleep 2

# Redémarrer VNC
vncserver "$VNC_DISPLAY" -geometry 1920x1080 -depth 24

# Redémarrer noVNC
cd "$INSTALL_DIR/noVNC"
export PATH="$PATH:$HOME/.local/bin"

if command -v websockify &> /dev/null; then
    websockify --web . "$PORT" localhost:"$VNC_PORT" > /dev/null 2>&1 &
elif [[ -f ./utils/novnc_proxy ]]; then
    ./utils/novnc_proxy --vnc localhost:"$VNC_PORT" --listen "$PORT" > /dev/null 2>&1 &
fi

echo "$!" > "$INSTALL_DIR/novnc.pid"
echo "✓ Services redémarrés"
echo "Interface: http://localhost:$PORT/vnc.html"
RESTARTSCRIPT
    
    # Script de statut
    cat > "$INSTALL_DIR/status-novnc.sh" << 'STATUSSCRIPT'
#!/bin/bash
INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$INSTALL_DIR/config.sh"

echo "═══════════════════════════════════════"
echo "  Statut des services noVNC"
echo "═══════════════════════════════════════"
echo ""

# Vérifier noVNC
if [[ -f "$INSTALL_DIR/novnc.pid" ]]; then
    PID=$(cat "$INSTALL_DIR/novnc.pid")
    if ps -p "$PID" > /dev/null 2>&1; then
        echo "✓ noVNC: ACTIF (PID: $PID, Port: $PORT)"
    else
        echo "✗ noVNC: INACTIF (PID obsolète: $PID)"
    fi
else
    echo "✗ noVNC: INACTIF (pas de PID)"
fi

# Vérifier VNC
if pgrep -f "Xvnc $VNC_DISPLAY" >/dev/null 2>&1; then
    VNC_PID=$(pgrep -f "Xvnc $VNC_DISPLAY")
    echo "✓ VNC: ACTIF (PID: $VNC_PID, Display: $VNC_DISPLAY, Port: $VNC_PORT)"
else
    echo "✗ VNC: INACTIF"
fi

echo ""
echo "Configuration:"
echo "  • Répertoire: $INSTALL_DIR"
echo "  • Display VNC: $VNC_DISPLAY"
echo "  • Port VNC: $VNC_PORT"
echo "  • Port noVNC: $PORT"
echo "  • URL: http://localhost:$PORT/vnc.html"
echo ""
STATUSSCRIPT
    
    # Fichier de configuration
    cat > "$INSTALL_DIR/config.sh" << CONFIGSCRIPT
#!/bin/bash
# Configuration noVNC
PORT="$PORT"
VNC_DISPLAY="$VNC_DISPLAY"
VNC_PORT="$VNC_PORT"
INSTALL_DIR="$INSTALL_DIR"
CONFIGSCRIPT
    
    # Rendre les scripts exécutables
    chmod +x "$INSTALL_DIR/stop-novnc.sh"
    chmod +x "$INSTALL_DIR/restart-novnc.sh"
    chmod +x "$INSTALL_DIR/status-novnc.sh"
    chmod +x "$INSTALL_DIR/config.sh"
    
    log_success "Scripts de gestion créés dans $INSTALL_DIR/"
}

# ============================================================================
# FONCTION PRINCIPALE
# ============================================================================
main() {
    # Bannière CLI
    cli_welcome
    
    # Détection de l'OS
    detect_os
    
    # Vérification TUI
    check_tui
    
    # Si TUI non disponible et mode interactif, installer automatiquement
    if ! $USE_TUI && [[ -t 0 ]] && [[ -t 1 ]] && ! $AUTO_MODE; then
        log_info "Installation automatique de l'interface TUI pour une meilleure expérience..."
        install_tui 2>/dev/null || log_info "TUI non installée, poursuite en mode CLI"
        check_tui
    fi
    
    # Interface utilisateur
    if $USE_TUI && ! $AUTO_MODE; then
        tui_welcome
        tui_configure
    elif ! $AUTO_MODE; then
        cli_welcome
        cli_configure
    else
        cli_welcome
        log_info "Mode automatique activé - utilisation des valeurs par défaut"
    fi
    
    # Installation
    install_dependencies
    install_websockify
    download_novnc
    setup_vnc_password
    create_xstartup
    start_vnc_server
    start_novnc
}

# ============================================================================
# AIDE
# ============================================================================
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

noVNC Universal Installer - Installation automatique pour toutes distributions Linux

OPTIONS:
  --port PORT          Port pour l'interface web noVNC (défaut: $DEFAULT_PORT)
  --display DISPLAY    Display VNC au format :N (défaut: $DEFAULT_VNC_DISPLAY)
  --password PASS      Mot de passe VNC (évite la saisie interactive)
  --skip-password      Utiliser le mot de passe par défaut 'novnc123'
  --no-tui             Forcer le mode CLI (sans interface TUI)
  --auto               Mode automatique (pas de questions, valeurs par défaut)
  --help, -h           Afficher cette aide

EXEMPLES:
  $0                                    # Mode interactif (TUI si disponible)
  $0 --port 8080 --display :2           # Configuration personnalisée
  $0 --password "monpass"               # Avec mot de passe prédéfini
  $0 --auto --skip-password             # Installation automatique sans interaction
  $0 --no-tui                           # Forcer le mode CLI
  $0 --port 6081 --display :1 --no-tui  # Combinaison d'options

DISTRIBUTIONS SUPPORTÉES:
  • Arch Linux, Manjaro, EndeavourOS, Garuda, ArcoLinux
  • Ubuntu, Debian, Linux Mint, Pop!_OS, Elementary, Kali
  • Fedora, RHEL, CentOS, Rocky Linux, AlmaLinux, Oracle Linux
  • openSUSE, SLES
  • Alpine Linux
  • Gentoo, Funtoo
  • Void Linux
  • Solus
  • NixOS

SCRIPTS CRÉÉS:
  • $HOME/novnc-setup/stop-novnc.sh      - Arrêter les services
  • $HOME/novnc-setup/restart-novnc.sh   - Redémarrer les services
  • $HOME/novnc-setup/status-novnc.sh    - Vérifier le statut

Pour plus d'informations: https://github.com/novnc/noVNC
EOF
}

# ============================================================================
# GESTION DES ARGUMENTS
# ============================================================================
AUTO_MODE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --port)
            PORT="$2"
            shift 2
            ;;
        --display)
            VNC_DISPLAY="$2"
            display_num="${VNC_DISPLAY/:/}"
            VNC_PORT=$((5900 + display_num))
            shift 2
            ;;
        --password)
            VNC_PASSWORD="$2"
            shift 2
            ;;
        --skip-password)
            SKIP_PASSWORD=true
            shift
            ;;
        --no-tui)
            USE_TUI=false
            shift
            ;;
        --auto)
            AUTO_MODE=true
            SKIP_PASSWORD=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Option inconnue: $1"
            echo "Utilisez --help pour l'aide"
            exit 1
            ;;
    esac
done

# ============================================================================
# EXÉCUTION
# ============================================================================

# Si mode auto, désactiver TUI et utiliser valeurs par défaut
if $AUTO_MODE; then
    USE_TUI=false
    log_info "Mode automatique activé"
fi

# Vérifier que le script n'est pas exécuté en root
if [[ $EUID -eq 0 ]]; then
    log_error "Ce script ne doit PAS être exécuté en tant que root"
    log_info "Il demandera sudo uniquement quand nécessaire"
    exit 1
fi

# Lancement
main
