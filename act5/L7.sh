#!/bin/bash

echo "================================="
echo " CONFIGURAR ACCESO ANONIMO FTP"
echo "================================="

CONF="/etc/vsftpd.conf"
CARPETA="/srv/ftp/general"

echo "Configurando acceso anonimo..."

# asegurar carpeta
mkdir -p $CARPETA

# permisos solo lectura
chmod 755 $CARPETA
chown nobody:nogroup $CARPETA

# modificar configuracion vsftpd
sed -i 's/^anonymous_enable=.*/anonymous_enable=YES/' $CONF

# añadir si no existen
grep -q "anon_root=" $CONF || echo "anon_root=$CARPETA" >> $CONF
grep -q "anon_upload_enable=" $CONF || echo "anon_upload_enable=NO" >> $CONF
grep -q "anon_mkdir_write_enable=" $CONF || echo "anon_mkdir_write_enable=NO" >> $CONF
grep -q "anon_other_write_enable=" $CONF || echo "anon_other_write_enable=NO" >> $CONF

# reiniciar servicio
systemctl restart vsftpd

echo ""
echo "Acceso anonimo configurado."
echo "Carpeta publica: $CARPETA"

echo ""
read -p "Presiona ENTER para continuar..."