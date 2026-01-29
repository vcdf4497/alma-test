# --- Configuration locale et fuseau horaire ---
ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc

locale-gen
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf

# --- Hostname et hosts ---
echo "ma-vm" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ma-vm.localdomain ma-vm
EOF

# --- Installation du bootloader GRUB pour BIOS ---
pacman -S --noconfirm grub
grub-install --target=i386-pc /dev/vda
grub-mkconfig -o /boot/grub/grub.cfg

# --- Installation des paquets pour interface graphique ---
pacman -S --noconfirm xorg xorg-xinit xfce4 xfce4-goodies lightdm lightdm-gtk-greeter networkmanager

# --- Activer le gestionnaire de session et le réseau ---
systemctl enable lightdm
systemctl enable NetworkManager

# --- Mot de passe root ---
echo "Définissez le mot de passe root :"
passwd

# --- Création d'un utilisateur non-root ---
echo "Création d'un utilisateur 'monuser' avec mot de passe"
useradd -m -G wheel monuser
passwd monuser

# --- Installer sudo et autoriser l'utilisateur à tout faire ---
pacman -S --noconfirm sudo
EDITOR=vim visudo <<EOF2
%wheel ALL=(ALL) ALL
EOF2

# --- Nettoyage et sortie ---
echo "Installation terminée ! Redémarrage dans 3 secondes..."
sleep 3
exit
umount -R /mnt
swapoff /dev/vda2
reboot
