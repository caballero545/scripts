#!/bin/bash

echo "Reiniciando servidor FTP..."

systemctl restart vsftpd
systemctl status vsftpd --no-pager

echo ""
echo "Servidor listo para probar."