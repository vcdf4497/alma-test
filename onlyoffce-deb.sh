#!/bin/bash

# --- CONFIGURATION ---
APP_NAME="OnlyOffice Desktop Editors"
DEB_URL="https://release-assets.githubusercontent.com/github-production-release-asset/69867298/cea8eb74-73bc-414c-b468-d3f75d15b78a?sp=r&sv=2018-11-09&sr=b&spr=https&se=2026-11-13T14%3A52%3A31Z&rscd=attachment%3B+filename%3Donlyoffice-desktopeditors_arm64.deb&rsct=application%2Foctet-stream&skoid=96c2d410-5711-43a1-aedd-ab1947aa7ab0&sktid=398a6654-997b-47e9-b12b-9515b896b4de&skt=2026-11-13T13%3A51%3A38Z&ske=2026-11-13T14%3A52%3A31Z&sks=b&skv=2018-11-09&sig=SqXaz1AFWsGJO32cB%2B6YjIarFXaw42n0I1ZGyIzf1NE%3D&jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmVsZWFzZS1hc3NldHMuZ2l0aHVidXNlcmNvbnRlbnQuY29tIiwia2V5Ijoia2V5MSIsImV4cCI6MTc5NDU4MTUzMiwibmJmIjoxNzk0NTc3OTMyLCJwYXRoIjoicmVsZWFzZWFzc2V0cHJvZHVjdGlvbi5ibG9iLmNvcmUud2luZG93cy5uZXQifQ.gqXDxRu9mfy_movIOlpQIAybpHd9PzSpIqFDtwE4gwk&response-content-disposition=attachment%3B%20filename%3Donlyoffice-desktopeditors_arm64.deb&response-content-type=application%2Foctet-stream"
DEB_FILE="onlyoffice-desktopeditors_arm64.deb"

# Couleurs pour l'affichage
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Installation interactive de ${APP_NAME} pour ChromeOS (Linux ARM64) ===${NC}"

# 1. Vérification de l'architecture
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ] && [ "$ARCH" != "arm64" ]; then
    echo -e "${RED}[Attention] Votre architecture système est '${ARCH}'. Ce lien est prévu pour ARM64 (aarch64). Voulez-vous continuer quand même ? (o/N)${NC}"
    read -r response
    if [[ ! "$response" =~ ^([oO][uU][iI]|[oO])$ ]]; then
        echo "Installation annulée."
        exit 1
    fi
fi

# 2. Confirmation interactive
echo -e "Ce script va :"
echo -e " 1. Mettre à jour la liste des paquets de votre environnement Linux."
echo -e " 2. Télécharger ${APP_NAME} (${DEB_FILE})."
echo -e " 3. Installer le paquet et corriger automatiquement les dépendances."
echo -e " 4. Configurer l'affichage pour que la fenêtre s'ouvre correctement sur votre bureau."
echo -e ""
read -p "Voulez-vous lancer l'installation maintenant ? (o/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Oo]$ ]]
then
    echo "Installation annulée par l'utilisateur."
    exit 0
fi

# 3. Mise à jour des dépôts
echo -e "${BLUE}[1/4] Mise à jour des listes de paquets...${NC}"
sudo apt update

# 4. Téléchargement du fichier .deb
echo -e "${BLUE}[2/4] Téléchargement d'OnlyOffice...${NC}"
if [ -f "$DEB_FILE" ]; then
    echo "Un fichier ${DEB_FILE} existe déjà. Utilisation du fichier existant..."
else
    wget -O "$DEB_FILE" "$DEB_URL"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Erreur lors du téléchargement. Veuillez vérifier votre connexion Internet.${NC}"
        exit 1
    fi
fi

# 5. Installation du paquet via apt (pour gérer automatiquement les dépendances)
echo -e "${BLUE}[3/4] Installation du paquet et résolution des dépendances...${NC}"
sudo apt install -y "./$DEB_FILE"
if [ $? -ne 0 ]; then
    echo -e "${RED}Erreur lors de l'installation du paquet .deb.${NC}"
    exit 1
fi

# 6. Configuration de l'affichage (Integration ChromeOS Linux GUI)
echo -e "${BLUE}[4/4] Configuration de l'affichage graphique...${NC}"
# S'assure que les variables d'environnement graphiques sont bien prises en compte
if [ -z "$DISPLAY" ]; then
    export DISPLAY=:0
fi

# Nettoyage optionnel du fichier .deb téléchargé
read -p "Voulez-vous supprimer le fichier d'installation .deb pour libérer de l'espace ? (o/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Oo]$ ]]
then
    rm "$DEB_FILE"
    echo "Fichier temporaire supprimé."
fi

echo -e "${GREEN}=== Installation terminée avec succès ! ===${NC}"
echo -e "Vous pouvez maintenant lancer ${APP_NAME} depuis le lanceur d'applications de votre Chromebook (dans le dossier 'Applications Linux')."
