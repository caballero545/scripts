#!/bin/bash

VHOME="/srv/ftp/vhome"

read -p "Usuario: " usuario

if ! id "$usuario" &>/dev/null; then
echo "Usuario no existe"
exit
fi

echo "1) reprobados"
echo "2) recursadores"

read op

if [ "$op" == "1" ]; then
nuevo="reprobados"
else
nuevo="recursadores"
fi

usermod -g $nuevo $usuario

echo "Grupo cambiado a $nuevo"

systemctl restart vsftpd