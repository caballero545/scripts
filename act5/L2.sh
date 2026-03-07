#!/bin/bash

BASE="/srv/ftp/usuarios"
VHOME="/srv/ftp/vhome"
FTP="/srv/ftp"

echo "=============================="
echo " CREACION DE USUARIOS FTP"
echo "=============================="

read -p "Cuantos usuarios deseas crear: " n

if ! [[ "$n" =~ ^[0-9]+$ ]]; then
echo "Debes escribir un número."
exit
fi

for ((i=1;i<=n;i++))
do

echo ""
echo "------ Usuario $i ------"

read -p "Nombre de usuario: " usuario

if id "$usuario" &>/dev/null; then
echo "El usuario ya existe."
i=$((i-1))
continue
fi

read -s -p "Contraseña: " pass
echo ""

echo "Grupo:"
echo "1) reprobados"
echo "2) recursadores"

read -p "Seleccione: " grp

if [ "$grp" == "1" ]; then
grupo="reprobados"
elif [ "$grp" == "2" ]; then
grupo="recursadores"
else
echo "Grupo inválido"
i=$((i-1))
continue
fi

carpeta="$BASE/$grupo/$usuario"
home="$VHOME/$usuario"

mkdir -p "$carpeta"
mkdir -p "$home"

useradd -d "$home" -s /sbin/nologin -g "$grupo" "$usuario"

echo "$usuario:$pass" | chpasswd

chown "$usuario:$grupo" "$carpeta"
chmod 770 "$carpeta"

# estructura visible en FTP

ln -s $FTP/general $home/general
ln -s $BASE/$grupo $home/$grupo
ln -s $carpeta $home/$usuario

chown root:root $home
chmod 755 $home

echo "Usuario $usuario creado correctamente."

done

echo ""
echo "Usuarios creados correctamente."

read -p "Presiona ENTER para continuar..."