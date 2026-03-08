#!/bin/bash

FTP="/srv/ftp"

echo "===== ARREGLANDO PERMISOS FTP ====="

# permisos base
chmod 755 /srv
chmod 755 $FTP
chmod 755 $FTP/vhome
chmod 755 $FTP/usuarios

# carpeta publica solo lectura para anonimos
chown root:root $FTP/general
chmod 755 $FTP/general

# carpetas de grupos
chown root:reprobados $FTP/usuarios/reprobados
chown root:recursadores $FTP/usuarios/recursadores

chmod 770 $FTP/usuarios/reprobados
chmod 770 $FTP/usuarios/recursadores

# setgid para mantener grupo
chmod g+s $FTP/usuarios/reprobados
chmod g+s $FTP/usuarios/recursadores

# arreglar permisos de homes ftp
for dir in $FTP/vhome/*; do
    if [ -d "$dir" ]; then

        user=$(basename "$dir")

        echo "Arreglando permisos para $user"

        chown -R $user:$user $dir

        chmod 755 $dir

        chmod 770 $dir/$user 2>/dev/null
        chmod 770 $dir/reprobados 2>/dev/null
        chmod 770 $dir/recursadores 2>/dev/null

        chmod 755 $dir/general 2>/dev/null
    fi
done

# permitir shell nologin
if ! grep -q "/sbin/nologin" /etc/shells; then
    echo "/sbin/nologin" >> /etc/shells
fi

systemctl restart vsftpd

echo "===== PERMISOS FTP PUESTOS CORRECTAMENTE ====="
echo ""
echo "===== VERIFICACION DEL SERVIDOR FTP ====="

echo ""
echo "--- Estado del servicio vsftpd ---"
systemctl is-active vsftpd

echo ""
echo "--- Usuarios FTP ---"
grep "/srv/ftp/vhome" /etc/passwd

echo ""
echo "--- Carpetas principales ---"
ls -ld /srv /srv/ftp /srv/ftp/general /srv/ftp/vhome /srv/ftp/usuarios

echo ""
echo "--- Carpetas de grupos ---"
ls -ld /srv/ftp/usuarios/reprobados
ls -ld /srv/ftp/usuarios/recursadores

echo ""
echo "--- Homes FTP ---"
ls -l /srv/ftp/vhome

echo ""
echo "--- Configuracion clave de vsftpd ---"
grep -E "anonymous_enable|anon_root|local_enable|write_enable|chroot_local_user|allow_writeable_chroot" /etc/vsftpd.conf

echo ""
echo "--- Shells permitidas ---"
grep nologin /etc/shells

echo ""
echo "===== FIN DE VERIFICACION ====="