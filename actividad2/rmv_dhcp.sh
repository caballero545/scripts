#!/bin/bash
# Detener el servicio
sudo systemctl stop isc-dhcp-server

# Eliminar el paquete y sus archivos de configuración
sudo apt-get purge -y isc-dhcp-server
sudo apt-get autoremove -y

# Borrar rastros de configuraciones y concesiones previas
sudo rm -rf /etc/dhcp/dhcpd.conf
sudo rm -rf /var/lib/dhcp/dhcpd.leases

echo "Servicio DHCP eliminado de Linux."