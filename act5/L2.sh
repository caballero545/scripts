#!/bin/bash

BASE="/srv/ftp/usuarios"
VHOME="/srv/ftp/vhome"
GENERAL="/srv/ftp/general"

echo "CREACION DE USUARIOS FTP"

read -p "Cuantos usuarios deseas crear: " n

for ((i=1;i<=n;i++))
do

read -p "Nombre de usuario: " usuario

if id "$usuario" &>/dev/null; then
echo "Usuario ya existe"
continue
fi

read -s -p "Contraseña: " pass
echo ""

echo "1) reprobados"
echo "2) recursadores"

read -p "Grupo: " g

if [ "$g" == "1" ]; then
grupo="reprobados"
elif [ "$g" == "2" ]; then
grupo="recursadores"
else
echo "Grupo invalido"
continue
fi

useradd -s /sbin/nologin -g "$grupo" "$usuario"

# agregar al grupo que puede escribir en general
usermod -aG ftpusers $usuario

echo "$usuario:$pass" | chpasswd

mkdir -p $VHOME/$usuario
mkdir -p $VHOME/$usuario/general
mkdir -p $VHOME/$usuario/$grupo
mkdir -p $VHOME/$usuario/$usuario

mount --bind $GENERAL $VHOME/$usuario/general
mount --bind $BASE/$grupo $VHOME/$usuario/$grupo

grep -q "$VHOME/$usuario/general" /etc/fstab || \
echo "$GENERAL $VHOME/$usuario/general none bind 0 0" >> /etc/fstab

grep -q "$VHOME/$usuario/$grupo" /etc/fstab || \
echo "$BASE/$grupo $VHOME/$usuario/$grupo none bind 0 0" >> /etc/fstab

systemctl daemon-reload
mount -a

chown root:root $VHOME/$usuario
chmod 755 $VHOME/$usuario

chown -R $usuario:$grupo $VHOME/$usuario/$usuario
chmod 770 $VHOME/$usuario/$usuario

usermod -d $VHOME/$usuario $usuario

echo "Usuario creado."

done

systemctl restart vsftpd