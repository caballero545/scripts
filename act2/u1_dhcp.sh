#!/bin/bash

dwnld_updt_dhcp() {
    if ! dpkg -l | grep -q isc-dhcp-server; then
        echo "--- Instalando isc-dhcp-server ---"
        sudo apt-get update && sudo apt-get install -y isc-dhcp-server
    else
        echo "El servicio DHCP ya está instalado en este sistema."
        read -p "¿Desea actualizar el servicio DHCP? (s/n): " r
        
        if [[ "$r" =~ ^[Ss]$ ]]; then
            echo "Actualizando isc-dhcp-server..."
            sudo apt-get update
            sudo apt-get install --only-upgrade -y isc-dhcp-server
        else
            echo "Se ha mantenido la versión actual."
        fi
    fi
    read -p "Presiona [Enter] para volver al menú..."
}
while true; do
	clear
	echo "------------------------------------------"
	echo "      MENU DE ADMINISTRACION DHCP"
	echo "------------------------------------------"
	echo "1. Descargar/actualizar DHCP"
	echo "2. Configurar DHCP"
	echo "3. Monitorear"
	echo "4. Salir"
	echo "------------------------------------------"

	read -p "Seleccione una opción (1-4): " opcn

	case $opcn in
    	1)
        	dwnld_updt_dhcp
        	;;
    	2)
        	echo "Esta opción se implementará en el siguiente paso."
        	;;
    	3)
        	echo "Módulo de monitoreo aún no disponible."
        	;;
    	4)
        	echo "Saliendo del script..."
        	exit 0
        	;;
    	*)
        	echo "Opción no válida. Intente de nuevo."
        	;;
	esac
done