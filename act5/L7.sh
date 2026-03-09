#!/bin/bash

echo "================================="
echo " CONFIGURAR ACCESO ANONIMO FTP"
echo "================================="

CONF="/etc/vsftpd.conf"
CARPETA="/srv/ftp/general"

echo "Configurando acceso anonimo..."

mkdir -p $CARPETA

# solo aseguramos lectura para otros
chmod 775 $CARPETA

# modificar configuracion
sed -i 's/^anonymous_enable=.*/anonymous_enable=YES/' $CONF

grep -q "anon_root=" $CONF || echo "anon_root=$CARPETA" >> $CONF
grep -q "anon_upload_enable=" $CONF || echo "anon_upload_enable=NO" >> $CONF
grep -q "anon_mkdir_write_enable=" $CONF || echo "anon_mkdir_write_enable=NO" >> $CONF
grep -q "anon_other_write_enable=" $CONF || echo "anon_other_write_enable=NO" >> $CONF
grep -q "local_umask=" $CONF || echo "local_umask=002" >> $CONF

systemctl restart vsftpd

echo ""
echo "Acceso anonimo configurado."
echo "Carpeta publica: $CARPETA"

echo ""
read -p "Presiona ENTER para continuar..."