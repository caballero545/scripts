#!/bin/bash

echo "===== CAMBIAR GRUPO DE USUARIO FTP ====="

read -p "Nombre del usuario: " usuario

# verificar si existe
if ! id "$usuario" &>/dev/null; then
    echo "El usuario no existe."
    exit
fi

echo "Seleccione nuevo grupo:"
echo "1) reprobados"
echo "2) recursadores"

read -p "Opción: " grupo

case $grupo in

1)
nuevo_grupo="reprobados"
;;

2)
nuevo_grupo="recursadores"
;;

*)
echo "Opción inválida"
exit
;;

esac

# cambiar grupo
usermod -g $nuevo_grupo $usuario

# actualizar permisos carpeta personal
chown $usuario:$nuevo_grupo /srv/ftp/usuarios/$usuario

echo "Grupo cambiado correctamente."
echo "El usuario ahora pertenece a: $nuevo_grupo"