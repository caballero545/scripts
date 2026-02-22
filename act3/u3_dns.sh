#!/bin/bash
# --- FUNCION 1: INSTALAR/REINSTALAR DHCP Y DNS ---
install_infrastructure() {
    echo "--- Instalando/Reinstalando DHCP y DNS (BIND9) ---"
    sudo apt-get update
    sudo apt-get install -y isc-dhcp-server bind9 bind9utils bind9-doc
    sudo systemctl restart isc-dhcp-server bind9
    echo "Servicios instalados y reiniciados."
    read -p "Presiona [Enter] para volver..."
}

# --- FUNCION 2: ESTABLECER IP FIJA (OBLIGATORIO) ---
set_static_ip() {
    echo "--- Paso 1: Establecer IP Fija del Servidor ---"
    ip -4 addr show | grep -E "eth|enp|inet "
    
    read -p "Ingrese el nombre de la interfaz (ej. enp0s8) o 'm' para menu: " INTERFACE
    [[ "$INTERFACE" == "m" ]] && return

    while true; do
        read -p "Ingrese la IP fija (ej. 112.12.12.1) o 'm': " IP_FIJA
        [[ "$IP_FIJA" == "m" ]] && return
        
        if [[ $IP_FIJA =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            # Extraer segmento y ultimo octeto para validaciones posteriores
            SEGMENTO=$(echo $IP_FIJA | cut -d'.' -f1-3)
            ULTIMO_OCTETO_FIJO=$(echo $IP_FIJA | cut -d'.' -f4)
            
            sudo ip addr flush dev $INTERFACE
            sudo ip addr add $IP_FIJA/24 dev $INTERFACE
            sudo ip link set $INTERFACE up
            
            # El DNS se asigna igual que la IP Fija
            DNS_SRV=$IP_FIJA
            echo "IP Fija y DNS configurados en $IP_FIJA"
            break
        else
            echo "Error: Formato de IP invalido."
        fi
    done
    read -p "Presiona [Enter] para continuar..."
}

# --- FUNCION 3: CONFIGURAR DHCP (VALIDACION +1) ---
configure_dhcp_pro() {
    if [[ -z "$IP_FIJA" ]]; then
        echo "ERROR: Primero debe establecer la IP Fija (Opcion 2)."
        read -p "Presiona [Enter] para volver..."
        return
    fi

    echo "--- Paso 2: Rango DHCP (IP Fija: $IP_FIJA) ---"
    
    # 1. Validacion IP Inicial (Debe ser Fija + 1)
    while true; do
        read -p "IP Inicial (Minimo: $SEGMENTO.$((ULTIMO_OCTETO_FIJO + 1))) o 'm': " IP_INI
        [[ "$IP_INI" == "m" ]] && return
        
        OCTETO_INI=$(echo $IP_INI | cut -d'.' -f4)
        SEG_INI=$(echo $IP_INI | cut -d'.' -f1-3)
        
        if [[ "$SEG_INI" == "$SEGMENTO" ]] && [ "$OCTETO_INI" -gt "$ULTIMO_OCTETO_FIJO" ]; then
            break
        else
            echo "Error: La IP debe ser mayor a $IP_FIJA y estar en la red $SEGMENTO.x"
        fi
    done

    # 2. Validacion IP Final
    while true; do
        read -p "IP Final (ej. $SEGMENTO.254) o 'm': " IP_FIN
        [[ "$IP_FIN" == "m" ]] && return
        
        OCTETO_FIN=$(echo $IP_FIN | cut -d'.' -f4)
        if [ "$OCTETO_FIN" -gt "$OCTETO_INI" ]; then
            break
        else
            echo "Error: La IP final debe ser mayor a la inicial ($IP_INI)."
        fi
    done

    # 3. Tiempo de Concesion
    while true; do
        read -p "Tiempo de concesion (segundos): " LEASE
        if [[ "$LEASE" =~ ^[0-9]+$ ]] && [ "$LEASE" -gt 0 ]; then break; fi
        echo "Error: Ingrese un numero positivo."
    done

    # Aplicar configuracion
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
    echo "Configuracion DHCP aplicada con DNS: $DNS_SRV"
    read -p "Presiona [Enter] para volver..."
}

# --- FUNCIONES DE DOMINIO (DNS BIND9) ---
create_domain() {
    read -p "Nombre del dominio (ej. aula.local) o 'm': " DOMINIO
    [[ "$DOMINIO" == "m" ]] && return
    
    ZONE_FILE="/etc/bind/db.$DOMINIO"
    sudo bash -c "cat > $ZONE_FILE" <<EOF
\$TTL 604800
@   IN  SOA ns.$DOMINIO. admin.$DOMINIO. (
                  1     ; Serial
             604800     ; Refresh
              86400     ; Retry
            2419200     ; Expire
             604800 )   ; Negative Cache TTL
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
    grep "zone" /etc/bind/named.conf.local
    read -p "Presiona [Enter] para volver..."
}

# --- MENU PRINCIPAL ---
while true; do
    clear
    echo "=============================================="
    echo "   SUITE INFRAESTRUCTURA LINUX (DHCP & DNS)"
    echo "=============================================="
    echo "1. Instalar/Reinstalar DHCP y DNS"
    echo "2. Establecer IP Fija (Servidor)"
    echo "3. Establecer Configuracion DHCP"
    echo "4. Monitorear DHCP"
    echo "5. Crear Dominio (DNS)"
    echo "6. Listar Dominios"
    echo "7. Ver Red (ip addr)"
    echo "8. Salir"
    read -p "Opcion: " op
    case $op in
        1) install_infrastructure ;;
        2) set_static_ip ;;
        3) configure_dhcp_pro ;;
        4) clear; sudo systemctl status isc-dhcp-server | grep Active; read -p "Enter..." ;;
        5) create_domain ;;
        6) list_domains ;;
        7) clear; ip addr; read -p "Enter..." ;;
        8) exit 0 ;;
    esac
done