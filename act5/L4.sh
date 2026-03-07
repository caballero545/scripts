#!/bin/bash

BASE="/srv/ftp/usuarios"

echo "================================="
echo " CAMBIAR GRUPO DE USUARIO FTP"
echo "================================="

read -p "Nombre del usuario: " usuario

# verificar usuario
if ! id "$usuario" &>/dev/null; then
    echo "Ese usuario no existe."
    exit
fi

# detectar grupo actual
if [ -d "$BASE/reprobados/$usuario" ]; then
    grupo_actual="reprobados"
elif [ -d "$BASE/recursadores/$usuario" ]; then
    grupo_actual="recursadores"
else
    echo "No se encontró la carpeta del usuario."
    exit
fi

echo "Grupo actual: $grupo_actual"

echo ""
echo "Seleccione nuevo grupo:"
echo "1) reprobados"
echo "2) recursadores"

read -p "Opción: " op

if [ "$op" == "1" ]; then
    nuevo_grupo="reprobados"
elif [ "$op" == "2" ]; then
    nuevo_grupo="recursadores"
else
    echo "Opción inválida"
    exit
fi

# si ya está en ese grupo
if [ "$grupo_actual" == "$nuevo_grupo" ]; then
    echo "El usuario ya pertenece a ese grupo."
    exit
fi

echo "Moviendo carpeta..."

mv "$BASE/$grupo_actual/$usuario" "$BASE/$nuevo_grupo/"

echo "Cambiando grupo en sistema..."

usermod -g "$nuevo_grupo" "$usuario"

echo "Actualizando permisos..."

chown -R "$usuario:$nuevo_grupo" "$BASE/$nuevo_grupo/$usuario"

VHOME="/srv/ftp/vhome"
HOMEUSER="$VHOME/$usuario"

rm -f $HOMEUSER/reprobados
rm -f $HOMEUSER/recursadores

ln -s $BASE/$nuevo_grupo $HOMEUSER/$nuevo_grupo

echo ""
echo "Grupo cambiado correctamente."
echo "El usuario ahora pertenece a: $nuevo_grupo"

echo ""
read -p "Presiona ENTER para continuar..."