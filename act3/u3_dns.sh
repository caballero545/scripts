#!/bin/bash
# =====================================================================
# SCRIPT DE ADMINISTRACIÓN DE RED (VERSIÓN FINAL PRO)
# =====================================================================
IP_FIJA=""
INTERFACE="enp0s8"
SEGMENTO=""
# --- FUNCIONES DE VALIDACIÓN ---
validar_ip_servidor() {
    local ip=$1
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 1; fi
    if [[ "$ip" == "0.0.0.0" ]] || [[ "$ip" == "255.255.255.255" ]] || \
       [[ "$ip" == "127.0.0.0" ]] || [[ "$ip" == "127.0.0.1" ]]; then
        echo -e "\e[31m[ERROR] IP prohibida para el servidor.\e[0m"; return 1
    fi
    return 0
}
validar_ip_dns() {
    local ip=$1
    [[ -z "$ip" ]] && return 0
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 1; fi
    if [[ "$ip" == "255.255.255.255" ]] || [[ "$ip" == "1.0.0.0" ]]; then
        echo -e "\e[31m[ERROR] IP prohibida para DNS.\e[0m"; return 1
    fi
    return 0
}
validar_mask() { [[ $1 =~ ^(255|254|252|248|240|224|192|128|0)\.(255|254|252|248|240|224|192|128|0)\.(255|254|252|248|240|224|192|128|0)\.(255|254|252|248|240|224|192|128|0)$ ]]; }

validar_tiempo() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]; }

limpiar_zonas_basura() { sudo sed -i '/zone ""/,/};/d' /etc/bind/named.conf.local; }
# --- 1. INSTALACIÓN ---
instalar_servicios() {
    echo -e "\n[+] Instalando DHCP y DNS..."
    sudo apt-get update && sudo apt-get install -y isc-dhcp-server bind9 bind9utils
    sudo systemctl enable isc-dhcp-server bind9
    read -p "Servicios instalados. Enter..."
}

# --- 2. CONFIGURACIÓN DE RED / DHCP (Desplazamiento +1) ---
configurar_sistema_principal() {
    echo -e "\n--- CONFIGURACIÓN DE RED (RANGO DESPLAZADO +1) ---"
    
    while true; do
        read -p "Inicio de rango (ej. 10.10.10.0): " R_INI
        if validar_ip_servidor "$R_INI"; then break; fi
    done

    while true; do
        read -p "Fin de rango (ej. 10.10.10.10): " R_FIN
        if validar_ip_servidor "$R_FIN"; then break; fi
    done

    IP_FIJA=$R_INI
    SEGMENTO=$(echo $IP_FIJA | cut -d'.' -f1-3)
    OCT_INI=$(echo $R_INI | cut -d'.' -f4)
    OCT_FIN=$(echo $R_FIN | cut -d'.' -f4)
    DHCP_START="${SEGMENTO}.$((OCT_INI + 1))"
    DHCP_END="${SEGMENTO}.$((OCT_FIN + 1))"

    while true; do
        read -p "Máscara [Enter para 255.255.255.0]: " MASK
        [[ -z "$MASK" ]] && MASK="255.255.255.0"
        if validar_mask "$MASK"; then break; fi
    done

    read -p "Gateway [Enter para vacío]: " GW

    while true; do
        read -p "DNS Primario [Opcional]: " DNS_1
        if validar_ip_dns "$DNS_1"; then break; fi
    done

    while true; do
        read -p "DNS Secundario [Opcional]: " DNS_2
        if [ -z "$DNS_2" ] || validar_ip_dns "$DNS_2"; then break; fi
    done

    while true; do
        read -p "Lease time (segundos): " LEASE
        if validar_tiempo "$LEASE"; then break; fi
    done

    # Aplicar IP a la interfaz
    sudo ip addr flush dev $INTERFACE
    sudo ip addr add $IP_FIJA/24 dev $INTERFACE
    sudo ip link set $INTERFACE up
    
    # FIX DEL PING: Apuntar el servidor a sí mismo
    echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf

    # FIX DE INTERNET: Forwarders para GitHub
    sudo bash -c "cat > /etc/bind/named.conf.options" <<EOF
options {
    directory "/var/cache/bind";
    forwarders { 8.8.8.8; 8.8.4.4; };
    dnssec-validation auto;
    listen-on-v6 { any; };
    allow-query { any; };
};
EOF

    # Configurar DHCP
    OPTS_DHCP=""
    [[ -n "$GW" ]] && OPTS_DHCP="${OPTS_DHCP}  option routers $GW;\n"
    if [[ -n "$DNS_1" ]]; then
        [[ -n "$DNS_2" ]] && DNS_VAL="$DNS_1, $DNS_2" || DNS_VAL="$DNS_1"
        OPTS_DHCP="${OPTS_DHCP}  option domain-name-servers $DNS_VAL;\n"
    fi

    sudo bash -c "cat > /etc/dhcp/dhcpd.conf" <<EOF
default-lease-time $LEASE;
max-lease-time $((LEASE * 2));
authoritative;
subnet ${SEGMENTO}.0 netmask $MASK {
  range $DHCP_START $DHCP_END;
$(echo -e "$OPTS_DHCP")
}
EOF

    sudo sed -i "s/INTERFACESv4=\".*\"/INTERFACESv4=\"$INTERFACE\"/" /etc/default/isc-dhcp-server
    limpiar_zonas_basura
    sudo systemctl restart bind9 isc-dhcp-server
    echo -e "\n[!] LISTO. IP Server: $IP_FIJA | Rango DHCP: $DHCP_START - $DHCP_END"
    read -p "Enter..."
}

# --- 3. DOMINIOS ---
add_dominio() {
    [[ -z "$IP_FIJA" ]] && { echo "Configure la red primero."; sleep 2; return; }
    read -p "Nombre del dominio (ej. reprobo.com): " DOM
    [[ -z "$DOM" ]] && return
    ZONE_FILE="/etc/bind/db.$DOM"
    sudo bash -c "cat > $ZONE_FILE" <<EOF
\$TTL 604800
@ IN SOA ns.$DOM. admin.$DOM. ( 1 604800 86400 2419200 604800 )
@ IN NS ns.$DOM.
ns IN A $IP_FIJA
@  IN A $IP_FIJA
EOF
    limpiar_zonas_basura
    sudo bash -c "echo 'zone \"$DOM\" { type master; file \"$ZONE_FILE\"; };' >> /etc/bind/named.conf.local"
    sudo systemctl restart bind9
    echo "Dominio '$DOM' añadido."; read -p "Enter..."
}

# --- 6. CHECK STATUS MEJORADO ---
check_status() {
    clear
    echo "==============================================="
    echo "         ESTADO GLOBAL DEL SISTEMA"
    echo "==============================================="
    
    echo -e "\n[1] INTERFAZ DE RED ($INTERFACE):"
    ip addr show $INTERFACE | grep -E "inet |link/" --color=always || echo "Interfaz no encontrada."

    echo -e "\n[2] SERVICIOS (SYSTEMD):"
    for srv in isc-dhcp-server bind9; do
        STATUS=$(systemctl is-active $srv)
        if [ "$STATUS" == "active" ]; then
            echo -e "$srv: \e[32m● ACTIVO\e[0m"
        else
            echo -e "$srv: \e[31m○ CAÍDO\e[0m"
        fi
    done

    echo -e "\n[3] PRUEBA DE SINTAXIS:"
    echo -n "DNS Config: " && sudo named-checkconf && echo -e "\e[32mOK\e[0m" || echo -e "\e[31mERROR\e[0m"
    echo -n "DHCP Config: " && sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf >/dev/null 2>&1 && echo -e "\e[32mOK\e[0m" || echo -e "\e[31mERROR\e[0m"

    echo -e "\n[4] ARCHIVO RESOLV.CONF (Resolución Local):"
    cat /etc/resolv.conf | grep "nameserver"

    echo -e "\n[5] ÚLTIMAS ASIGNACIONES DHCP:"
    sudo tail -n 5 /var/lib/dhcp/dhcpd.leases | grep -E "lease|hardware|client-hostname" || echo "Sin concesiones recientes."
    
    echo "==============================================="
    read -p "Presione Enter para volver al menú..."
}

# --- MENÚ ---
while true; do
    clear
    echo "==============================================="
    echo "      SISTEMA DE ADMINISTRACIÓN DE RED"
    echo "==============================================="
    echo " IP ACTUAL SERVER: ${IP_FIJA:-PENDIENTE}"
    echo "-----------------------------------------------"
    echo "1. Instalar DHCP/DNS"
    echo "2. Configurar Rango / Red / DHCP (Desplazado +1)"
    echo "3. Añadir Dominio DNS"
    echo "4. Eliminar Dominio DNS"
    echo "5. Listar Dominios"
    echo "6. VER STATUS DETALLADO"
    echo "7. Salir"
    echo "-----------------------------------------------"
    read -p "Opción: " op
    case $op in
        1) instalar_servicios ;;
        2) configurar_sistema_principal ;;
        3) add_dominio ;;
        4) read -p "Dominio: " D; sudo sed -i "/zone \"$D\"/d" /etc/bind/named.conf.local; sudo systemctl restart bind9; read -p "OK." ;;
        5) grep "zone" /etc/bind/named.conf.local | cut -d'"' -f2; read -p "..." ;;
        6) check_status ;;
        7) exit 0 ;;
    esac
done