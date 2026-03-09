#!/bin/bash

if [ "$EUID" -ne 0 ]; then
echo "Ejecuta como root"
exit
fi

FTP="/srv/ftp"

echo "===== ARREGLANDO PERMISOS FTP ====="

sudo chmod 755 /srv
sudo chmod 755 $FTP
sudo chmod 755 $FTP/vhome
sudo chmod 755 $FTP/usuarios

sudo chown root:ftpusers $FTP/general
sudo chmod 775 $FTP/general

sudo chown root:reprobados $FTP/usuarios/reprobados
sudo chown root:recursadores $FTP/usuarios/recursadores

sudo chmod 770 $FTP/usuarios/reprobados
sudo chmod 770 $FTP/usuarios/recursadores

sudo chmod g+s $FTP/usuarios/reprobados
sudo chmod g+s $FTP/usuarios/recursadores

for dir in $FTP/vhome/*; do
    if [ -d "$dir" ]; then

        user=$(basename "$dir")

        echo "Arreglando permisos para $user"

        sudo chown root:root $dir
        sudo chmod 755 $dir

        sudo chown -R $user:$user $dir/$user 2>/dev/null
        sudo chmod 770 $dir/$user 2>/dev/null
    fi
done

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