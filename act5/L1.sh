#!/bin/bash

if [ "$EUID" -ne 0 ]; then
echo "Ejecuta como root"
exit
fi

echo "===== CONFIGURANDO FTP ====="

apt update -y
apt install vsftpd -y

groupadd reprobados 2>/dev/null
groupadd recursadores 2>/dev/null

mkdir -p /srv/ftp/general
mkdir -p /srv/ftp/usuarios/reprobados
mkdir -p /srv/ftp/usuarios/recursadores
mkdir -p /srv/ftp/vhome

chmod 755 /srv
chmod 755 /srv/ftp
chmod 755 /srv/ftp/vhome
chmod 777 /srv/ftp/general

chown root:reprobados /srv/ftp/usuarios/reprobados
chown root:recursadores /srv/ftp/usuarios/recursadores

chmod 770 /srv/ftp/usuarios/reprobados
chmod 770 /srv/ftp/usuarios/recursadores

cp /etc/vsftpd.conf /etc/vsftpd.conf.bak

cat > /etc/vsftpd.conf <<EOF
listen=YES
anonymous_enable=YES
anon_root=/srv/ftp/general

local_enable=YES
write_enable=YES

chroot_local_user=YES
allow_writeable_chroot=YES

pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
EOF

systemctl enable vsftpd
systemctl restart vsftpd

echo "FTP configurado."