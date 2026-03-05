#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "Ejecuta con sudo."
    exit
fi

while true
do

clear

echo "================================="
echo "       ADMINISTRADOR FTP"
echo "================================="
echo "1) Instalar / reparar FTP"
echo "2) Crear usuarios FTP"
echo "3) Configurar permisos FTP"
echo "4) Cambiar grupo de usuario"
echo "5) Ver usuarios FTP"
echo "6) Eliminar usuario FTP"
echo "7) Configurar FTP anonimo"
echo "0) Salir"
echo "================================="

read -p "Seleccione una opcion: " op

case $op in

1)
bash ./L1.sh
read -p "Presiona ENTER para continuar"
;;

2)
bash ./L2.sh
read -p "Presiona ENTER para continuar"
;;

3)
bash ./L3.sh
read -p "Presiona ENTER para continuar"
;;

4)
bash ./L4.sh
read -p "Presiona ENTER para continuar"
;;

5)
bash ./L5.sh
read -p "Presiona ENTER para continuar"
;;

6)
bash ./L6.sh
read -p "Presiona ENTER para continuar"
;;

7)
bash ./L7.sh
read -p "Presiona ENTER para continuar"
;;

0)
exit
;;

*)
echo "Opcion invalida"
sleep 2
;;

esac

done