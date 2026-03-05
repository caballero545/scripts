#!/bin/bash

BASE="/srv/ftp"

echo "=============================="
echo " CREACION DE USUARIOS FTP"
echo "=============================="

read -p "Cuantos usuarios deseas crear: " n

for ((i=1;i<=n;i++))
do

echo ""
echo "------ Usuario $i ------"

read -p "Nombre de usuario: " usuario
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

# Crear usuario en Linux
useradd -m -d $BASE/usuarios/$usuario -s /usr/sbin/nologin $usuario

echo "$usuario:$pass" | chpasswd

# agregar a grupo
usermod -aG $grupo $usuario

# Crear carpeta personal
mkdir -p $BASE/usuarios/$usuario

# Permisos
chown $usuario:$grupo $BASE/usuarios/$usuario
chmod 770 $BASE/usuarios/$usuario

echo "Usuario $usuario creado correctamente."

done

echo ""
echo "Usuarios creados correctamente."