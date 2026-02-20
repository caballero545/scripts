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
    # Sub-función para validar formato e IPs prohibidas
    validar_ip_estricta() {
        local ip=$1
        # Permitir vacíos para Gateway/DNS opcionales
        if [[ -z "$ip" ]]; then return 0; fi

        # Validar formato básico num.num.num.num
        if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            OIFS=$IFS; IFS='.'; ip_partes=($ip); IFS=$OIFS
            
            # 1. Validar que cada octeto sea 0-255
            for i in "${ip_partes[@]}"; do
                if [[ $i -gt 255 ]]; then return 1; fi
            done

            # 2. Bloqueo de IPs prohibidas solicitadas
            if [[ "$ip" == "0.0.0.0" || "$ip" == "255.255.255.255" || "$ip" == "1.0.0.0" ]]; then 
                return 1 
            fi
            
            # 3. Bloquear todo el rango de loopback (127.x.x.x)
            if [[ "${ip_partes[0]}" == "127" ]]; then return 1; fi

            return 0
        fi
        return 1
    }

    ip_a_entero() {
        local a b c d
        IFS=. read -r a b c d <<< "$1"
        echo "$(( (a << 24) + (b << 16) + (c << 8) + d ))"
    }

    echo "--- Configuración de Parámetros DHCP ---"

    # 1. IP Inicial (Obligatoria y Estricta)
    while true; do
        read -p "Ingrese la IP Inicial: " IP_INI
        if [[ -n "$IP_INI" ]] && validar_ip_estricta "$IP_INI"; then
            SEGMENTO=$(echo $IP_INI | cut -d'.' -f1-3)
            break
        else
            echo "Error: IP inválida, vacía o reservada"
        fi
    done

    # 2. IP Final (Obligatoria, Estricta y Coherente)
    while true; do
        read -p "Ingrese la IP Final: " IP_FIN
        if [[ -n "$IP_FIN" ]] && validar_ip_estricta "$IP_FIN"; then
            SEG_FIN=$(echo $IP_FIN | cut -d'.' -f1-3)
            if [ "$SEGMENTO" != "$SEG_FIN" ]; then
                echo "Error: Debe estar en la red $SEGMENTO.x"
                continue
            fi
            if [ $(ip_a_entero "$IP_INI") -le $(ip_a_entero "$IP_FIN") ]; then
                break
            else
                echo "Error: La IP inicial no puede ser mayor que la final."
            fi
        else
            echo "Error: IP inválida o reservada."
        fi
    done

    # 3. Gateway (Opcional, pero si se pone, se valida)
   while true; do
        read -p "Ingrese Gateway (Opcional, Enter para omitir): " GATEWAY
        if [[ -z "$GATEWAY" ]] || validar_ip_estricta "$GATEWAY"; then 
            break
        else 
            echo "Error: IP de Gateway inválida o prohibida (1.0.0.0, 255.255.255.255, 127.x)."
        fi
    done

    # 4. DNS (Opcional, con bloqueo de 1.0.0.0 y 255.255.255.255)
    while true; do
        read -p "Ingrese DNS (Opcional, Enter para omitir): " DNS_SRV
        if [[ -z "$DNS_SRV" ]] || validar_ip_estricta "$DNS_SRV"; then 
            break
        else 
            echo "Error: IP de DNS inválida o prohibida (1.0.0.0, 255.255.255.255, 127.x)."
        fi
    done

    # 5. Tiempo de Concesión
    while true; do
        read -p "Tiempo de concesión en segundos: " LEASE_TIME
        if [[ "$LEASE_TIME" =~ ^[0-9]+$ ]]; then break;
        else echo "Error: Ingrese solo números."; fi
    done

    echo "=========================================="
    echo "CONFIGURACIÓN LISTA PARA APLICAR"
    echo "Rango: $IP_INI - $IP_FIN"
    echo "Gateway: ${GATEWAY:-Ninguno}"
    echo "DNS: ${DNS_SRV:-Ninguno}"
    echo "Lease: $LEASE_TIME seg"
    echo "=========================================="
    read -p "Presiona [Enter] para volver al menú..."
}

aplicar_configuracion_dhcp() {
    if [[ -z "$IP_INI" || -z "$IP_FIN" ]]; then
        echo "Error: Primero debes ingresar los datos en la Opción 2."
        read -p "Presiona [Enter] para volver..."
        return
    fi

    echo "Aplicando cambios en /etc/dhcp/dhcpd.conf..."

    # Escribir el archivo
    sudo bash -c "cat > /etc/dhcp/dhcpd.conf" <<EOF
# Configuración generada por Script Automatizado
option domain-name "red.local";
default-lease-time $LEASE_TIME;
max-lease-time $((LEASE_TIME * 2));

authoritative;

subnet ${SEGMENTO}.0 netmask 255.255.255.0 {
  range $IP_INI $IP_FIN;
  $( [[ -n "$GATEWAY" ]] && echo "option routers $GATEWAY;" )
  $( [[ -n "$DNS_SRV" ]] && echo "option domain-name-servers $DNS_SRV;" )
  option subnet-mask 255.255.255.0;
  option broadcast-address ${SEGMENTO}.255;
}
EOF

    # Validar y Reiniciar
    echo "Validando archivo de configuración..."
    if sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf; then
        echo "Sintaxis correcta. Reiniciando servicio..."
        sudo systemctl restart isc-dhcp-server
        sudo systemctl enable isc-dhcp-server
        echo "=========================================="
        echo "¡SERVIDOR DHCP ACTIVO Y CONFIGURADO!"
        echo "=========================================="
    else
        echo "Error crítico: La configuración generada es inválida."
    fi
    
    read -p "Presiona [Enter] para volver al menú..."
}

# --- FUNCIÓN DE MONITOREO Y VALIDACIÓN ---

monitorear_dhcp() {
    clear
    echo "=========================================="
    echo "      ESTADO DEL SERVIDOR DHCP"
    echo "=========================================="
    
    # 1. Verificar si el servicio está corriendo (Active: active (running))
    echo "--- Estado del Servicio ---"
    sudo systemctl is-active isc-dhcp-server > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "ESTADO: [ ACTIVO ]"
    else
        echo "ESTADO: [ INACTIVO/ERROR ]"
    fi
    echo "------------------------------------------"

    # 2. Listar las concesiones (leases) activas
    # Se extraen del archivo /var/lib/dhcp/dhcpd.leases
    echo "--- Equipos Conectados (Leases) ---"
    if [ -f /var/lib/dhcp/dhcpd.leases ]; then
        # Este comando filtra IPs y nombres de host para que sea legible
        grep -E "lease|hostname" /var/lib/dhcp/dhcpd.leases | sort | uniq
    else
        echo "No se encontraron registros de concesiones activos."
    fi
    echo "=========================================="
    
    # 3. Sugerencia de prueba de cliente
    echo "TIP: Para probar, ejecuta 'ipconfig /renew' en tu Windows cliente."
    echo "=========================================="
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
        	configurar_rango_dhcp
		aplicar_configuracion_dhcp
        	;;
    	3)
        	monitorear_dhcp
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