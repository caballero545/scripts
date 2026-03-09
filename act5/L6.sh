#!/bin/bash

BASE="/srv/ftp/usuarios"
VHOME="/srv/ftp/vhome"

echo "=============================="
echo "      ELIMINAR USUARIO FTP"
echo "=============================="

echo ""
echo "Usuarios FTP existentes:"
echo "------------------------"

# Listamos los usuarios basándonos en sus carpetas personales
find "$VHOME" -maxdepth 1 -mindepth 1 -type d -printf "%f\n"

echo ""
read -p "Escribe el nombre del usuario a eliminar: " usuario

# Verificar si existe en el sistema
if ! id "$usuario" &>/dev/null; then
    echo "Ese usuario no existe."
    read -p "Presiona ENTER para continuar..."
    exit
fi

# Detectar grupo del usuario
grupo=$(id -gn "$usuario")

echo ""
echo "Desmontando carpetas compartidas de $usuario..."

# desmontaje seguro
umount -l "$VHOME/$usuario/general" 2>/dev/null
umount -l "$VHOME/$usuario/$grupo" 2>/dev/null

# limpiar fstab
sed -i "/\/vhome\/$usuario\//d" /etc/fstab

# recargar systemd porque modificamos fstab
systemctl daemon-reload

echo "Eliminando usuario y archivos personales..."

# eliminar usuario del sistema
userdel -f "$usuario" 2>/dev/null

# borrar carpetas
rm -rf "$BASE/reprobados/$usuario" 2>/dev/null
rm -rf "$BASE/recursadores/$usuario" 2>/dev/null
rm -rf "$VHOME/$usuario"

echo ""
echo "Usuario $usuario eliminado correctamente."

echo ""
read -p "Presiona ENTER para continuar..."