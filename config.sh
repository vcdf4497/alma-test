ln -sf /usr/share/zoneinfo/Europe/Paris /etc/localtime
hwclock --systohc

echo "fr_FR.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=fr_FR.UTF-8" > /etc/locale.conf

echo "ma-vm" > /etc/hostname
cat <<EOF > /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   ma-vm.localdomain ma-vm
EOF
