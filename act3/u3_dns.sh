#!/bin/bash

install_infrastructure() {
    echo "--- Instalar/Reinstalar DHCP y DNS (BIND9) ---"
    sudo apt-get update
    sudo apt-get install -y isc-dhcp-server bind9 bind9utils bind9-doc
    sudo systemctl restart isc-dhcp-server bind9
    echo "Servicios instalados y reiniciados."
    read -p "Presiona [Enter] para volver..."
}

set_static_ip() {
    echo "--- Paso 1: Establecer IP Fija del Servidor ---"
    ip -4 addr show | grep -E "eth|enp|inet "
    
    read -p "Ingrese el nombre de la interfaz (ej...enp0s8) o 'm' para volver al menu: " INTERFACE
    [[ "$INTERFACE" == "m" ]] && return

    while true; do
        read -p "Ingrese la IP fija (ej. 11.11.11.2) o 'm': " IP_FIJA
        [[ "$IP_FIJA" == "m" ]] && return
        
        if [[ $IP_FIJA =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            SEGMENTO=$(echo $IP_FIJA | cut -d'.' -f1-3)
            ULTIMO_OCTETO_FIJO=$(echo $IP_FIJA | cut -d'.' -f4)
            GATEWAY_PRO="${SEGMENTO}.1"
            
            sudo ip addr flush dev $INTERFACE
            sudo ip addr add $IP_FIJA/24 dev $INTERFACE
            sudo ip link set $INTERFACE up
            
            DNS_SRV=$IP_FIJA
            echo "IP Fija: $IP_FIJA | Gateway sugerido: $GATEWAY_PRO"
            break
        else
            echo "Error: Formato de IP invalido"
        fi
    done
    read -p "Presiona [Enter] para continuar..."
}

configure_dhcp_pro() {
    if [[ -z "$IP_FIJA" ]]; then
        echo "ERROR: Primero debe establecer la IP Fija (Opcion 2)"
        read -p "Presiona [Enter] para volver..."
        return
    fi

    echo "--- Paso 2: Rango DHCP (IP Fija: $IP_FIJA) ---"
    while true; do
        read -p "IP Inicial (Minimo: $SEGMENTO.$((ULTIMO_OCTETO_FIJO + 1))) o 'm': " IP_INI
        [[ "$IP_INI" == "m" ]] && return
        OCTETO_INI=$(echo $IP_INI | cut -d'.' -f4)
        SEG_INI=$(echo $IP_INI | cut -d'.' -f1-3)
        if [[ "$SEG_INI" == "$SEGMENTO" ]] && [ "$OCTETO_INI" -gt "$ULTIMO_OCTETO_FIJO" ]; then break
        else echo "Error: La IP debe ser mayor a $IP_FIJA"; fi
    done

    while true; do
        read -p "IP Final (ej. $SEGMENTO.254) o 'm': " IP_FIN
        [[ "$IP_FIN" == "m" ]] && return
        OCTETO_FIN=$(echo $IP_FIN | cut -d'.' -f4)
        if [ "$OCTETO_FIN" -gt "$OCTETO_INI" ]; then break
        else echo "Error: La IP final debe ser mayor a la inicial."; fi
    done

    read -p "Tiempo de concesion (seg): " LEASE
    GATEWAY_FORZADO="${SEGMENTO}.1"

    sudo sed -i "s/INTERFACESv4=\".*\"/INTERFACESv4=\"$INTERFACE\"/" /etc/default/isc-dhcp-server
    sudo bash -c "cat > /etc/dhcp/dhcpd.conf" <<EOF
default-lease-time $LEASE;
max-lease-time $((LEASE * 2));
authoritative;
subnet ${SEGMENTO}.0 netmask 255.255.255.0 {
  range $IP_INI $IP_FIN;
  option routers $GATEWAY_FORZADO;
  option domain-name-servers $DNS_SRV;
}
EOF
    sudo systemctl restart isc-dhcp-server
    echo "DHCP Activo. Gateway: $GATEWAY_FORZADO"
    read -p "Presiona [Enter] para volver..."
}

create_domain() {
    while true; do
        read -p "Nombre del dominio (ej. aprobados.com) o 'm': " DOMINIO
        [[ "$DOMINIO" == "m" ]] && return
        
        # Validación: ¿Está vacío?
        if [[ -z "$DOMINIO" ]]; then
            echo -e "\e[31mError: El nombre del dominio no puede estar vacío.\e[0m"
        # Validación: ¿Tiene un formato mínimo? (letras.letras)
        elif [[ ! "$DOMINIO" =~ \. ]]; then
            echo -e "\e[31mError: Formato inválido. Debe incluir un punto (ej. dominio.com).\e[0m"
        else
            break
        fi
    done

    ZONE_FILE="/etc/bind/db.$DOMINIO"
    
    # Formato limpio para BIND9
    sudo bash -c "cat > $ZONE_FILE" <<EOF
\$TTL 604800
@ IN SOA ns.$DOMINIO. admin.$DOMINIO. ( 1 604800 86400 2419200 604800 )
@ IN NS ns.$DOMINIO.
ns IN A $IP_FIJA
EOF

    sudo bash -c "echo 'zone \"$DOMINIO\" { type master; file \"$ZONE_FILE\"; };' >> /etc/bind/named.conf.local"
    sudo chown bind:bind "$ZONE_FILE"
    sudo chmod 644 "$ZONE_FILE"
    sudo systemctl restart bind9
    echo "Dominio $DOMINIO creado con éxito."
    read -p "Presiona [Enter] para volver..."
}

list_domains() {
    echo "=== Dominios Configurados ==="
    grep "zone" /etc/bind/named.conf.local | cut -d'"' -f2
    read -p "Presiona [Enter] para volver..."
}
remove_domain() {
    while true; do
        read -p "Ingrese el nombre del dominio a Eliminar o 'm': " DOM_DEL
        [[ "$DOM_DEL" == "m" ]] && return
        
        if [[ -z "$DOM_DEL" ]]; then
            echo -e "\e[31mError: No puedes dejar el nombre vacío.\e[0m"
        else
            break
        fi
    done
    
    # Validación de existencia
    if ! grep -q "zone \"$DOM_DEL\"" /etc/bind/named.conf.local; then
        echo -e "\e[31mError: El dominio '$DOM_DEL' no existe en el servidor.\e[0m"
        read -p "Presiona [Enter] para volver..."
        return
    fi

    echo "Eliminando $DOM_DEL..."
    sudo sed -i "/zone \"$DOM_DEL\"/,/};/d" /etc/bind/named.conf.local
    sudo rm -f "/etc/bind/db.$DOM_DEL"
    sudo rndc flush
    sudo systemctl restart bind9
    
    echo "Dominio $DOM_DEL eliminado correctamente."
    read -p "Presiona [Enter] para volver..."
}
monitor_clients() {
    clear
    echo "=== ESTADO DEL SERVICIO DHCP ==="
    sudo systemctl status isc-dhcp-server | grep "Active:"
    echo -e "\n=== EQUIPOS CONECTADOS ==="
    [ -f /var/lib/dhcp/dhcpd.leases ] && grep "lease" /var/lib/dhcp/dhcpd.leases | sort | uniq || echo "Sin clientes."
    read -p "Presiona [Enter] para volver..."
}

while true; do
    clear
    echo "=============================================="
    echo "LINUX (DHCP & DNS) - Gateway .1"
    echo "=============================================="
    echo "1. Instalar/Reinstalar"
    echo "2. IP Fija (Servidor)"
    echo "3. Configurar DHCP"
    echo "4. Monitor"
    echo "5. Crear Dominio"
    echo "6. Eliminar Dominio"
    echo "7. Listar Dominios"
    echo "8. Ver Red"
    echo "9. Salir"
    read -p "Opcion: " op
    case $op in
        1) install_infrastructure ;;
        2) set_static_ip ;;
        3) configure_dhcp_pro ;;
        4) monitor_clients ;;
        5) create_domain ;;
        6) remove_domain ;;
        7) list_domains ;;
        8) clear; ip addr; read -p "Enter..." ;;
        9) exit 0 ;;
    esac
done