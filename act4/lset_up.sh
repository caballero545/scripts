#!/bin/bash

echo "--- PREPARANDO SERVIDOR PARA ADMINISTRACIÓN REMOTA ---"

# 1. Instalar SSH (Tu captura decía que no existía, aquí lo forzamos)
sudo apt-get update
sudo apt-get install -y openssh-server

# 2. Habilitar y arrancar el servicio
sudo systemctl enable ssh
sudo systemctl start ssh

# 3. Configurar credenciales del usuario actual (papu)
echo "Configura/Valida la contraseña para el usuario '$(whoami)':"
sudo passwd $(whoami)

# 4. Asegurar que tenga permisos de sudo para los scripts de DNS/DHCP
sudo usermod -aG sudo $(whoami)

echo "--- LISTO ---"
echo "IP del servidor: $(hostname -I | cut -d' ' -f1)"
echo "Ahora puedes ir al CLIENTE y bajar los scripts."