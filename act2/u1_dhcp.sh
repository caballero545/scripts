#!/bin/bash
if ! dpkg -l | grep -q isc-dhcp-server; then
    echo "Instalando isc-dhcp-server..."
    sudo apt-get update && sudo apt-get install -y isc-dhcp-server
else
    echo "El servicio ya está instalado."
    # Preguntar al usuario si desea actualizar
    read -p "¿Desea actualizar el servicio DHCP? (s/n): " resp
    
    if [[ "$resp" =~ ^[Ss]$ ]]; then
        echo "Actualizando isc-dhcp-server..."
        sudo apt-get update
        sudo apt-get install --only-upgrade -y isc-dhcp-server
    else
        echo "Se ha mantenido la versión actual."
    fi
fi