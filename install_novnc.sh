#!/bin/bash
set -e

PORT=6081
VNC_DISPLAY=:1
VNC_PORT=5901

echo "[+] Installation des dépendances (pacman)"
sudo pacman -Syu --needed --noconfirm git python tigervnc

echo "[+] Installation de websockify via pip"
pip install --user websockify

echo "[+] Téléchargement de noVNC 1.6.0"
[ -d noVNC ] || git clone --branch v1.6.0 --depth 1 https://github.com/novnc/noVNC.git

echo "[+] Lancement du serveur VNC ($VNC_DISPLAY)"
pgrep -f "Xvnc $VNC_DISPLAY" >/dev/null || vncserver $VNC_DISPLAY

echo "[+] Lancement de noVNC (port $PORT)"
export PATH="$HOME/.local/bin:$PATH"  # pour que websockify installé par pip soit trouvé
cd noVNC
./utils/novnc_proxy --vnc localhost:$VNC_PORT --listen $PORT
