#!/bin/bash
# =====================================================================
# SCRIPT DE ADMINISTRACIÓN INTEGRAL: DHCP & DNS (FIX INTERNET & PING)
# =====================================================================

IP_FIJA=""
INTERFACE="enp0s8"
SEGMENTO=""

# --- VALIDACIONES ---
validar_ip_servidor() {
    local ip=$1
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 1; fi
    if [[ "$ip" == "0.0.0.0" ]] || [[ "$ip" == "255.255.255.255" ]] || \
       [[ "$ip" == "127.0.0.0" ]] || [[ "$ip" == "127.0.0.1" ]]; then
        echo -e "\e[31m[ERROR] IP prohibida.\e[0m"; return 1
    fi
    return 0
}

validar_ip_dns() {
    local ip=$1
    [[ -z "$ip" ]] && return 0
    if [[ "$ip" == "255.255.255.255" ]] || [[ "$ip" == "1.0.0.0" ]]; then
        echo -e "\e[31m[ERROR] DNS prohibido.\e[0m"; return 1
    fi
    return 0
}

validar_mask() { [[ $1 =~ ^(255|254|252|248|240|224|192|128|0)\.(255|254|252|248|240|224|192|128|0)\.(255|254|252|248|240|224|192|128|0)\.(255|254|252|248|240|224|192|128|0)$ ]]; }

validar_tiempo() { [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]; }

limpiar_zonas_basura() { sudo sed -i '/zone ""/,/};/d' /etc/bind/named.conf.local; }

# --- 1. INSTALACIÓN ---
instalar_servicios() {
    echo -e "\n[+] Instalando Servicios..."
    sudo apt-get update && sudo apt-get install -y isc-dhcp-server bind9 bind9utils
    sudo systemctl enable isc-dhcp-server bind9
    read -p "Servicios listos. Enter..."
}

# --- 2. CONFIGURACIÓN DE RED / DHCP / DNS ---
configurar_sistema_principal() {
    echo -e "\n--- CONFIGURACIÓN DE RED Y RANGO DHCP ---"
    
    while true; do
        read -p "Ingrese inicio de rango (IP Fija Server): " R_INI
        if validar_ip_servidor "$R_INI"; then break; fi
    done

    while true; do
        read -p "Ingrese fin de rango: " R_FIN
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

    read -p "Puerta de enlace (Gateway): " GW

    while true; do
        read -p "DNS Primario (Clientes): " DNS_1
        if validar_ip_dns "$DNS_1"; then break; fi
    done

    while true; do
        read -p "Lease time (segundos): " LEASE
        if validar_tiempo "$LEASE"; then break; fi
    done

    # --- APLICAR RED ---
    sudo ip addr flush dev $INTERFACE
    sudo ip addr add $IP_FIJA/24 dev $INTERFACE
    sudo ip link set $INTERFACE up
    
    # FIX: Configurar el servidor para que se use a sí mismo como DNS
    echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf

    # FIX: Configurar Reenviadores en BIND para tener internet
    sudo bash -c "cat > /etc/bind/named.conf.options" <<EOF
options {
    directory "/var/cache/bind";
    forwarders {
        8.8.8.8;
        8.8.4.4;
    };
    dnssec-validation auto;
    listen-on-v6 { any; };
    allow-query { any; };
};
EOF

    # --- CONFIGURAR DHCP ---
    OPTS_DHCP=""
    [[ -n "$GW" ]] && OPTS_DHCP="${OPTS_DHCP}  option routers $GW;\n"
    [[ -n "$DNS_1" ]] && OPTS_DHCP="${OPTS_DHCP}  option domain-name-servers $DNS_1;\n"

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
    sudo systemctl restart bind9
    sudo systemctl restart isc-dhcp-server
    
    echo -e "\n[!] LISTO: Server en $IP_FIJA | DNS Local e Internet habilitados."
    read -p "Enter..."
}

# --- 3. DOMINIOS ---
add_dominio() {
    [[ -z "$IP_FIJA" ]] && { echo "Configura la red primero."; sleep 2; return; }
    read -p "Nombre del dominio: " DOM
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
    echo "Dominio '$DOM' activo."; read -p "Enter..."
}

# --- MENÚ ---
while true; do
    clear
    echo "=== ADMIN REMOTO (IP: ${IP_FIJA:-PENDIENTE}) ==="
    echo "1. Instalar DHCP/DNS"
    echo "2. Configurar Rango / Red / DHCP"
    echo "3. Añadir Dominio DNS"
    echo "4. Eliminar Dominio DNS"
    echo "5. Listar Dominios"
    echo "6. Status del Sistema"
    echo "7. Salir"
    read -p "Opción: " op
    case $op in
        1) instalar_servicios ;;
        2) configurar_sistema_principal ;;
        3) add_dominio ;;
        4) read -p "Dominio: " D; sudo sed -i "/zone \"$D\"/d" /etc/bind/named.conf.local; sudo systemctl restart bind9; read -p "OK." ;;
        5) grep "zone" /etc/bind/named.conf.local | cut -d'"' -f2; read -p "..." ;;
        6) clear; systemctl is-active isc-dhcp-server bind9; ip addr show $INTERFACE | grep "inet "; read -p "Enter..." ;;
        7) exit 0 ;;
    esac
done