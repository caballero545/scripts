#!/bin/bash

# ===============================
#  FTP SERVER BASE SETUP (LINUX)
# ===============================

# --- Verificar root ---
if [ "$EUID" -ne 0 ]; then
    echo "Ejecuta este script como root o con sudo."
    exit 1
fi

echo "===== INICIANDO CONFIGURACIÓN BASE FTP ====="

# --- 1. Instalación idempotente de vsftpd ---
if ! dpkg -l | grep -q vsftpd; then
    echo "Instalando vsftpd..."
    apt update -y
    apt install vsftpd -y
else
    echo "vsftpd ya está instalado."
fi

echo "Creando grupos necesarios..."

groupadd reprobados 2>/dev/null
groupadd recursadores 2>/dev/null

# --- 2. Crear estructura base ---
echo "Creando estructura base en /srv/ftp..."

mkdir -p /srv/ftp/general
mkdir -p /srv/ftp/vhome
mkdir -p /srv/ftp/usuarios/reprobados
mkdir -p /srv/ftp/usuarios/recursadores

# --- 3. Permisos básicos iniciales ---
chmod 777 /srv/ftp/general
chown root:reprobados /srv/ftp/usuarios/reprobados
chown root:recursadores /srv/ftp/usuarios/recursadores
chmod 770 /srv/ftp/usuarios/reprobados
chmod 770 /srv/ftp/usuarios/recursadores
chmod 755 /srv/ftp
chmod 755 /srv/ftp/vhome
chmod 755 /srv/ftp/general

# (Los permisos finos se asignarán después en fase de usuarios)

# --- 4. vsftpd ---
echo "Configurando vsftpd..."

cp /etc/vsftpd.conf /etc/vsftpd.conf.bak

cat > /etc/vsftpd.conf <<EOF
listen=YES

anonymous_enable=YES
anon_root=/srv/ftp/general

local_enable=YES
write_enable=YES

chroot_local_user=YES
allow_writeable_chroot=YES

pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
EOF

# --- 5. Reiniciar y habilitar servicio ---
systemctl enable vsftpd
systemctl restart vsftpd

echo "===== CONFIGURACIÓN BASE COMPLETADA ====="
echo "Estructura creada en /srv/ftp"
echo "Servicio vsftpd activo."