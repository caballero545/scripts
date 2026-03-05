#!/bin/bash

echo "===== CONFIGURANDO PERMISOS FTP ====="

FTP_ROOT="/srv/ftp"

# asegurar carpetas base
mkdir -p $FTP_ROOT/general
mkdir -p $FTP_ROOT/reprobados
mkdir -p $FTP_ROOT/recursadores
mkdir -p $FTP_ROOT/usuarios

# permisos base
chmod 755 $FTP_ROOT
chmod 777 $FTP_ROOT/general

# asignar grupos
chgrp reprobados $FTP_ROOT/reprobados
chgrp recursadores $FTP_ROOT/recursadores

# permisos de grupo
chmod 770 $FTP_ROOT/reprobados
chmod 770 $FTP_ROOT/recursadores

# carpeta usuarios
chmod 755 $FTP_ROOT/usuarios

echo "Permisos configurados correctamente"