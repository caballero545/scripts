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
        read -p "Ingrese la IP fija (ej. 112.12.12.1) o 'm': " IP_FIJA
        [[ "$IP_FIJA" == "m" ]] && return
        
        if [[ $IP_FIJA =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            SEGMENTO=$(echo $IP_FIJA | cut -d'.' -f1-3)
            ULTIMO_OCTETO_FIJO=$(echo $IP_FIJA | cut -d'.' -f4)
            
            sudo ip addr flush dev $INTERFACE
            sudo ip addr add $IP_FIJA/24 dev $INTERFACE
            sudo ip link set $INTERFACE up
            
            DNS_SRV=$IP_FIJA
            echo "IP Fija y DNS configurados en $IP_FIJA"
            break
        else
            echo "Error Formato de IP invalido"
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
        else echo "Error: La IP debe ser mayor a $IP_FIJA en la red $SEGMENTO.x"; fi
    done

    while true; do
        read -p "IP Final (ej. $SEGMENTO.254) o 'm': " IP_FIN
        [[ "$IP_FIN" == "m" ]] && return
        OCTETO_FIN=$(echo $IP_FIN | cut -d'.' -f4)
        if [ "$OCTETO_FIN" -gt "$OCTETO_INI" ]; then break
        else echo "Error: La IP final debe ser mayor a la inicial ($IP_INI)."; fi
    done

    read -p "Tiempo de concesion (seg): " LEASE
    sudo sed -i "s/INTERFACESv4=\".*\"/INTERFACESv4=\"$INTERFACE\"/" /etc/default/isc-dhcp-server
    sudo bash -c "cat > /etc/dhcp/dhcpd.conf" <<EOF
default-lease-time $LEASE;
max-lease-time $((LEASE * 2));
authoritative;
subnet ${SEGMENTO}.0 netmask 255.255.255.0 {
  range $IP_INI $IP_FIN;
  option routers $IP_FIJA;
  option domain-name-servers $DNS_SRV;
}
EOF
    sudo systemctl restart isc-dhcp-server
    echo "DHCP Activo."
    read -p "Presiona [Enter] para volver..."
}
create_domain() {
    read -p "Nombre del dominio (ej. google.com) o 'm': " DOMINIO
    [[ "$DOMINIO" == "m" ]] && return
    ZONE_FILE="/etc/bind/db.$DOMINIO"
    sudo bash -c "cat > $ZONE_FILE" <<EOF
\$TTL 604800
@   IN  SOA ns.$DOMINIO. admin.$DOMINIO. ( 1; 604800; 86400; 2419200; 604800 )
@   IN  NS  ns.$DOMINIO.
ns  IN  A   $IP_FIJA
EOF
    sudo bash -c "echo 'zone \"$DOMINIO\" { type master; file \"$ZONE_FILE\"; };' >> /etc/bind/named.conf.local"
    sudo systemctl restart bind9
    echo "Dominio $DOMINIO creado."
    read -p "Presiona [Enter] para volver..."
}

list_domains() {
    echo "=== Dominios Configurados ==="
    grep "zone" /etc/bind/named.conf.local | cut -d'"' -f2
    read -p "Presiona [Enter] para volver..."
}
remove_domain() {
    read -p "Ingrese el nombre del dominio a Eliminar o 'm': " DOM_DEL
    [[ "$DOM_DEL" == "m" ]] && return
    
    # Validacion corregida: Buscamos si existe la zona antes de intentar borrar
    if ! grep -q "zone \"$DOM_DEL\"" /etc/bind/named.conf.local; then
        # Usamos -e para que el codigo de color \e[31m (Rojo) funcione en Linux
        echo -e "\e[31mError: El dominio '$DOM_DEL' no existe en el servidor.\e[0m"
        read -p "Presiona [Enter] para volver..."
        return
    fi

    echo "Eliminando rastro de $DOM_DEL..."
    sudo sed -i "/zone \"$DOM_DEL\"/,/};/d" /etc/bind/named.conf.local
    sudo rm -f "/etc/bind/db.$DOM_DEL"
    sudo rndc flush 2>/dev/null
    sudo systemctl restart bind9
    
    echo "Dominio $DOM_DEL eliminado correctamente de la memoria y el disco"
    read -p "Presiona [Enter] para volver..."
}
monitor_clients() {
    clear
    echo "=== ESTADO DEL SERVICIO DHCP ==="
    sudo systemctl status isc-dhcp-server | grep "Active:"
    
    echo -e "\n=== EQUIPOS CONECTADOS (CONCESIONES) ==="
    # Buscamos en el archivo real de concesiones de Linux
    if [ -f /var/lib/dhcp/dhcpd.leases ]; then
        grep -E "lease|hardware ethernet|client-hostname" /var/lib/dhcp/dhcpd.leases | \
        sed 's/lease //g; s/hardware ethernet //g; s/client-hostname //g; s/ [{;]//g' | \
        awk 'ORS=NR%3?", ":" \n"' | sort | uniq
    else
        echo "No hay registros de clientes todavia."
    fi
    echo "----------------------------------------------"
    read -p "Presiona [Enter] para volver..."
}
while true; do
    clear
    echo "=============================================="
    echo "LINUX (DHCP & DNS)"
    echo "=============================================="
    echo "1. Instalar/Reinstalar DHCP y DNS"
    echo "2. Establecer IP Fija (Servidor)"
    echo "3. Configurar DHCP"
    echo "4. Monitorea DHCP (Clientes)"
    echo "5. Crear Dominio (DNS)"
    echo "6. Eliminar Dominio"
    echo "7. Listar Dominios"
    echo "8. Ver Red (ip addr)"
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