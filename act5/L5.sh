#!/bin/bash

BASE="/srv/ftp/usuarios"

echo "================================="
echo " USUARIOS FTP REGISTRADOS"
echo "================================="
echo ""
printf "%-15s %-15s %-30s\n" "USUARIO" "GRUPO" "CARPETA"
echo "-------------------------------------------------------------"

total=0

for grupo in reprobados recursadores
do
    for carpeta in $BASE/$grupo/*
    do
        if [ -d "$carpeta" ]; then
            usuario=$(basename "$carpeta")

            printf "%-15s %-15s %-30s\n" "$usuario" "$grupo" "$carpeta"

            total=$((total+1))
        fi
    done
done

echo ""
echo "Total usuarios: $total"

echo ""
read -p "Presiona ENTER para continuar..."