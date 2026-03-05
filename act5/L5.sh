#!/bin/bash

echo "===== USUARIOS FTP REGISTRADOS ====="
echo ""

printf "%-15s %-15s %-30s\n" "USUARIO" "GRUPO" "CARPETA"
echo "--------------------------------------------------------------"

for user in $(ls /srv/ftp/usuarios)
do

    grupo=$(id -gn $user 2>/dev/null)

    carpeta="/srv/ftp/usuarios/$user"

    printf "%-15s %-15s %-30s\n" "$user" "$grupo" "$carpeta"

done

echo ""
echo "Total usuarios: $(ls /srv/ftp/usuarios | wc -l)"