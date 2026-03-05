#!/bin/bash

BASE="/srv/ftp/usuarios"

echo "=============================="
echo " CREACION DE USUARIOS FTP"
echo "=============================="

read -p "Cuantos usuarios deseas crear: " n

# validar que sea numero
if ! [[ "$n" =~ ^[0-9]+$ ]]; then
    echo "Debes ingresar un numero."
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

# carpeta personal
carpeta="$BASE/$grupo/$usuario"

mkdir -p "$BASE/$grupo"

useradd -m -d "$carpeta" -s /sbin/nologin -g "$grupo" "$usuario"

echo "$usuario:$pass" | chpasswd

mkdir -p "$carpeta"

chown -R "$usuario:$grupo" "$carpeta"
chmod 770 "$carpeta"

echo "Usuario $usuario creado correctamente en grupo $grupo."

done

echo ""
echo "Usuarios creados correctamente."