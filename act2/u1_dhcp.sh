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

configurar_rango_dhcp() {
    # Sub-función interna para validar formato IP (0-255)
    validar_ip() {
        local ip=$1
        if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            OIFS=$IFS; IFS='.'; ip_partes=($ip); IFS=$OIFS
            [[ ${ip_partes[0]} -le 255 && ${ip_partes[1]} -le 255 && \
               ${ip_partes[2]} -le 255 && ${ip_partes[3]} -le 255 ]]
            return $?
        fi
        return 1
    }

    # Sub-función interna para convertir IP a número
    ip_a_entero() {
        local a b c d
        IFS=. read -r a b c d <<< "$1"
        echo "$(( (a << 24) + (b << 16) + (c << 8) + d ))"
    }

    echo "--- Configuración de Parámetros DHCP ---"

    # 1. Pedir y validar IP Inicial
    while true; do
        read -p "Ingrese la IP Inicial (ej. 192.168.100.50): " IP_INI
        if validar_ip "$IP_INI"; then
            SEGMENTO=$(echo $IP_INI | cut -d'.' -f1-3)
            break
        else
            echo "Error: Formato de IP inválido. Intente de nuevo."
        fi
    done

    # 2. Pedir y validar IP Final
    while true; do
        read -p "Ingrese la IP Final (ej. 192.168.100.150): " IP_FIN
        if validar_ip "$IP_FIN"; then
            SEG_FIN=$(echo $IP_FIN | cut -d'.' -f1-3)
            if [ "$SEGMENTO" != "$SEG_FIN" ]; then
                echo "Error: La IP final debe pertenecer a la red $SEGMENTO.x"
                continue
            fi

            INI_NUM=$(ip_a_entero "$IP_INI")
            FIN_NUM=$(ip_a_entero "$IP_FIN")

            if [ "$INI_NUM" -le "$FIN_NUM" ]; then
                break
            else
                echo "Error: La IP inicial ($IP_INI) no puede ser mayor que la final ($IP_FIN)."
            fi
        else
            echo "Error: Formato de IP inválido. Intente de nuevo."
        fi
    done

    # 3. Pedir Tiempo de Concesión (Lease Time) en segundos
    while true; do
        read -p "Ingrese el tiempo de concesión en segundos (ej. 600): " LEASE_TIME
        # Validar que sea solo números y no esté vacío
        if [[ "$LEASE_TIME" =~ ^[0-9]+$ ]]; then
            break
        else
            echo "Error: Por favor ingrese un valor numérico válido para el tiempo."
        fi
    done

    echo "=========================================="
    echo "Rango validado: $IP_INI - $IP_FIN"
    echo "Segmento de red: $SEGMENTO.0"
    echo "Tiempo de concesión: $LEASE_TIME segundos"
    echo "=========================================="
    read -p "Presiona [Enter] para continuar..."
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
        	configurar_rango_dhcp
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