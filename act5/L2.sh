#!/bin/bash

BASE="/srv/ftp/usuarios"

echo "=============================="
echo " CREACION DE USUARIOS FTP"
echo "=============================="

read -p "Cuantos usuarios deseas crear: " n

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
exit
fi

BASE="/srv/ftp/usuarios"

# carpeta personal del usuario dentro del grupo
carpeta="$BASE/$grupo/$usuario"

# asegurar que exista la carpeta del grupo
mkdir -p "$BASE/$grupo"

# Crear usuario en Linux
useradd -m -d "$carpeta" -s /sbin/nologin -g "$grupo" "$usuario"

# asignar contraseña
echo "$usuario:$pass" | chpasswd

# asegurar carpeta personal
mkdir -p "$carpeta"

# Permisos
chown -R "$usuario:$grupo" "$carpeta"
chmod 770 "$carpeta"

done

echo "Usuario $usuario creado correctamente en grupo $grupo."