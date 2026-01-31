#!/bin/bash
set -e

PORT=6081
VNC_DISPLAY=:1
VNC_PORT=5901

echo "[+] Installation des dépendances"
sudo pacman -Sy --needed --noconfirm \
  git \
  python \
  python-websockify \
  tigervnc

echo "[+] Téléchargement de noVNC 1.6.0"
if [ ! -d "noVNC" ]; then
  git clone --branch v1.6.0 --depth 1 https://github.com/novnc/noVNC.git
fi

echo "[+] Lancement du serveur VNC ($VNC_DISPLAY)"
if ! pgrep -f "Xvnc $VNC_DISPLAY" >/dev/null; then
  vncserver $VNC_DISPLAY
fi

echo "[+] Lancement de noVNC (port $PORT)"
cd noVNC
./utils/novnc_proxy --vnc localhost:$VNC_PORT --listen $PORT
