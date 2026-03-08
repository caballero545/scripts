#!/bin/bash

BASE="/srv/ftp/usuarios"
VHOME="/srv/ftp/vhome"

read -p "Usuario: " usuario

if [ -d "$BASE/reprobados/$usuario" ]; then
grupo="reprobados"
elif [ -d "$BASE/recursadores/$usuario" ]; then
grupo="recursadores"
else
echo "No existe"
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

mv $BASE/$grupo/$usuario $BASE/$nuevo/

rm -rf $VHOME/$usuario/$grupo
mkdir $VHOME/$usuario/$nuevo

chown -R $usuario:$nuevo $BASE/$nuevo/$usuario

usermod -g $nuevo $usuario

systemctl restart vsftpd