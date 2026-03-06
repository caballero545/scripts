#!/bin/bash

echo "================================="
echo " CONFIGURANDO ESTRUCTURA FTP"
echo "================================="

FTP="/srv/ftp"
BASE="/srv/ftp/usuarios"

echo "Creando enlaces simbolicos..."

for grupo in reprobados recursadores
do
    for carpeta in $BASE/$grupo/*
    do
        if [ -d "$carpeta" ]; then

            usuario=$(basename "$carpeta")

            echo "Configurando usuario: $usuario"

            # enlace a general
            ln -sf $FTP/general $carpeta/general

            # enlace a carpeta del grupo
            ln -sf $BASE/$grupo $carpeta/$grupo

        fi
    done
done

echo ""
echo "Estructura FTP configurada."

read -p "Presiona ENTER para continuar..."