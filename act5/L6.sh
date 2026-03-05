#!/bin/bash

BASE="/srv/ftp/usuarios"

echo "=============================="
echo " ELIMINAR USUARIO FTP"
echo "=============================="

echo ""
echo "Usuarios FTP existentes:"
echo "------------------------"

# mostrar usuarios dentro de carpetas FTP
find $BASE -mindepth 2 -maxdepth 2 -type d -printf "%f\n"

echo ""
read -p "Escribe el nombre del usuario a eliminar: " usuario

# verificar si existe
if id "$usuario" &>/dev/null; then

    echo "Eliminando usuario..."

    sudo userdel -r "$usuario"

    # borrar carpeta si quedara algo
    rm -rf $BASE/reprobados/$usuario
    rm -rf $BASE/recursadores/$usuario

    echo "Usuario eliminado correctamente."

else
    echo "Ese usuario no existe."
fi

echo ""
read -p "Presiona ENTER para continuar..."