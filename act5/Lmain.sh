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

0)
exit
;;

*)
echo "Opcion invalida"
sleep 2
;;

esac

done