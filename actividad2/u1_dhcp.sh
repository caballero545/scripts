#!/bin/bash
if ! dpkg -l | grep -q isc-dhcp-server; then
    echo "Instalando isc-dhcp-server..."
    sudo apt-get update && sudo apt-get install -y isc-dhcp-server
else
    echo "El servicio ya está instalado."
fi