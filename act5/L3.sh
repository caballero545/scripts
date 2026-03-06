#!/bin/bash

echo "===== CONFIGURANDO PERMISOS FTP ====="

FTP_ROOT="/srv/ftp"
USER_ROOT="/srv/ftp/usuarios"

# asegurar carpetas base
mkdir -p $FTP_ROOT/general
mkdir -p $USER_ROOT/reprobados
mkdir -p $USER_ROOT/recursadores

# permisos base
chmod 755 $FTP_ROOT
chmod 777 $FTP_ROOT/general

# asignar grupos
chgrp reprobados $USER_ROOT/reprobados
chgrp recursadores $USER_ROOT/recursadores

# permisos de grupo
chmod 770 $USER_ROOT/reprobados
chmod 770 $USER_ROOT/recursadores

# carpeta usuarios
chmod 755 $USER_ROOT

echo "Permisos configurados correctamente"

read -p "Presiona ENTER para continuar..."