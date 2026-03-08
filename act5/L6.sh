#!/bin/bash

BASE="/srv/ftp/usuarios"
VHOME="/srv/ftp/vhome"

echo "=============================="
echo " ELIMINAR USUARIO FTP"
echo "=============================="

echo ""
echo "Usuarios FTP existentes:"
echo "------------------------"

find "$BASE" -mindepth 2 -maxdepth 2 -type d -printf "%f\n"

echo ""
read -p "Escribe el nombre del usuario a eliminar: " usuario

# verificar si existe
if ! id "$usuario" &>/dev/null; then
    echo "Ese usuario no existe."
    read -p "Presiona ENTER para continuar..."
    exit
fi

echo ""
echo "Eliminando usuario..."

# eliminar usuario sin mostrar advertencias
userdel -r "$usuario" 2>/dev/null

# borrar carpetas por seguridad
rm -rf "$BASE/reprobados/$usuario"
rm -rf "$BASE/recursadores/$usuario"
rm -rf "$VHOME/$usuario"

rm -rf /srv/ftp/vhome/$usuario

echo "Usuario eliminado correctamente."

echo ""
read -p "Presiona ENTER para continuar..."