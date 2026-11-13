#!/usr/bin/env bash

# --- CONFIGURATION ---
APP_NAME="OnlyOffice Desktop Editors"
DEB_URL="https://release-assets.githubusercontent.com/github-production-release-asset/69867298/cea8eb74-73bc-414c-b468-d3f75d15b78a?sp=r&sv=2018-11-09&sr=b&spr=https&se=2026-11-13T14%3A52%3A31Z&rscd=attachment%3B+filename%3Donlyoffice-desktopeditors_arm64.deb&rsct=application%2Foctet-stream&skoid=96c2d410-5711-43a1-aedd-ab1947aa7ab0&sktid=398a6654-997b-47e9-b12b-9515b896b4de&skt=2026-11-13T13%3A51%3A38Z&ske=2026-11-13T14%3A52%3A31Z&sks=b&skv=2018-11-09&sig=SqXaz1AFWsGJO32cB%2B6YjIarFXaw42n0I1ZGyIzf1NE%3D&jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmVsZWFzZS1hc3NldHMuZ2l0aHVidXNlcmNvbnRlbnQuY29tIiwia2V5Ijoia2V5MSIsImV4cCI6MTc5NDU4MTUzMiwibmJmIjoxNzk0NTc3OTMyLCJwYXRoIjoicmVsZWFzZWFzc2V0cHJvZHVjdGlvbi5ibG9iLmNvcmUud2luZG93cy5uZXQifQ.gqXDxRu9mfy_movIOlpQIAybpHd9PzSpIqFDtwE4gwk&response-content-disposition=attachment%3B%20filename%3Donlyoffice-desktopeditors_arm64.deb&response-content-type=application%2Foctet-stream"
DEB_FILE="/tmp/onlyoffice-desktopeditors_arm64.deb"

# Couleurs
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Installation de ${APP_NAME} pour ChromeOS (Linux ARM64) ===${NC}"

# 1. Vérification de l'architecture
ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" && "$ARCH" != "arm64" ]]; then
    echo -e "${RED}[Attention] Architecture détectée : '${ARCH}'. Ce paquet est conçu pour ARM64 (aarch64).${NC}"
    printf "Continuer malgré tout ? (o/N) : "
    read -r response < /dev/tty
    if [[ ! "$response" =~ ^([oO][uU][iI]|[oO])$ ]]; then
        echo "Installation annulée."
        exit 1
    fi
fi

# 2. Confirmation interactive compatible curl | bash
echo ""
echo "Ce script va :"
echo "  1. Mettre à jour les dépôts APT"
echo "  2. Télécharger ${APP_NAME}"
echo "  3. Installer le paquet et ses dépendances"
echo "  4. Configurer l'affichage pour ChromeOS"
echo ""
printf "Voulez-vous lancer l'installation maintenant ? (o/N) : "
read -r reply < /dev/tty

if [[ ! "$reply" =~ ^([oO][uU][iI]|[oO])$ ]]; then
    echo "Installation annulée."
    exit 0
fi

# 3. Mise à jour des dépôts
echo -e "${BLUE}[1/4] Mise à jour des listes de paquets...${NC}"
sudo apt update

# 4. Téléchargement dans /tmp pour éviter d'encombrer le dossier personnel
echo -e "${BLUE}[2/4] Téléchargement d'OnlyOffice...${NC}"
wget -O "$DEB_FILE" "$DEB_URL"
if [ $? -ne 0 ]; then
    echo -e "${RED}Erreur lors du téléchargement. Vérifiez que le lien n'a pas expiré.${NC}"
    exit 1
fi

# 5. Installation via apt
echo -e "${BLUE}[3/4] Installation du paquet et des dépendances...${NC}"
sudo apt install -y "$DEB_FILE"
if [ $? -ne 0 ]; then
    echo -e "${RED}Erreur lors de l'installation du paquet .deb.${NC}"
    exit 1
fi

# 6. Configuration graphique & nettoyage
echo -e "${BLUE}[4/4] Finalisation et nettoyage...${NC}"
if [ -z "$DISPLAY" ]; then
    export DISPLAY=:0
fi

rm -f "$DEB_FILE"

echo -e "${GREEN}=== Installation terminée avec succès ! ===${NC}"
echo "Vous pouvez lancer OnlyOffice depuis le menu 'Applications Linux' de votre Chromebook."
