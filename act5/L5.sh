#!/bin/bash

# Ahora usamos VHOME como referencia principal ya que ahí están los montajes
VHOME="/srv/ftp/vhome"

echo "================================="
echo "    USUARIOS FTP REGISTRADOS"
echo "================================="
echo ""
printf "%-15s %-15s %-30s\n" "USUARIO" "GRUPO" "HOME REAL"
echo "-------------------------------------------------------------"

total=0

# Listamos los directorios en vhome
for carpeta_home in $VHOME/*
do
    if [ -d "$carpeta_home" ]; then
        usuario=$(basename "$carpeta_home")
        
        # Obtenemos el grupo primario del usuario
        grupo=$(id -gn "$usuario" 2>/dev/null)
        
        # Si el usuario existe en el sistema, lo mostramos
        if [ $? -eq 0 ]; then
            printf "%-15s %-15s %-30s\n" "$usuario" "$grupo" "$carpeta_home"
            total=$((total+1))
        fi
    fi
done

echo ""
echo "Total usuarios activos: $total"
echo "-------------------------------------------------------------"
echo "Nota: La carpeta /general es compartida mediante montajes bind."

echo ""
read -p "Presiona ENTER para continuar..."