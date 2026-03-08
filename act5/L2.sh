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
echo "$usuario:$pass" | chpasswd

mkdir -p $BASE/$grupo/$usuario

mkdir -p $VHOME/$usuario
mkdir -p $VHOME/$usuario/general
mkdir -p $VHOME/$usuario/$grupo
mkdir -p $VHOME/$usuario/$usuario

cp -r $GENERAL/* $VHOME/$usuario/general 2>/dev/null

chown -R $usuario:$grupo $BASE/$grupo/$usuario
chown -R $usuario:$grupo $VHOME/$usuario/$usuario
chown -R $usuario:$grupo $VHOME/$usuario/$grupo

chmod 770 $BASE/$grupo/$usuario
chmod 770 $VHOME/$usuario/$usuario
chmod 770 $VHOME/$usuario/$grupo

usermod -d $VHOME/$usuario $usuario

echo "Usuario creado."

done

systemctl restart vsftpd