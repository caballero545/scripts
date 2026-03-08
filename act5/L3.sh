#!/bin/bash

FTP="/srv/ftp"

chmod 755 $FTP
chmod 755 $FTP/vhome
chmod 777 $FTP/general

chgrp reprobados $FTP/usuarios/reprobados
chgrp recursadores $FTP/usuarios/recursadores

chmod 770 $FTP/usuarios/reprobados
chmod 770 $FTP/usuarios/recursadores

echo "Permisos configurados."

systemctl restart vsftpd