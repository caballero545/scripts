#!/bin/bash
# dns_functions.sh - Lógica pura

# --- 1. INSTALACIÓN ---
instalar_servicios() {
    echo "--- Instalando ISC-DHCP-SERVER, BIND9 y SSH ---"
    sudo apt-get update && sudo apt-get install -y isc-dhcp-server bind9 bind9utils openssh-server
    sudo systemctl enable --now ssh
    sudo systemctl enable isc-dhcp-server bind9
    echo "Servicios listos."
    read -p "Presiona Enter..."
}

# --- 2. IP FIJA ---
# Esta función ahora devuelve los datos para que el MAIN los guarde
establecer_ip_fija_logic() {
    local interface="enp0s8"
    read -p "Ingrese la IP Fija (ej. 77.77.77.7) o [r]: " IP_ING
    if [[ "$IP_ING" == "r" ]]; then echo "CANCEL"; return; fi
    
    if [[ $IP_ING =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        sudo ip addr flush dev $interface
        sudo ip addr add $IP_ING/24 dev $interface
        sudo ip link set $interface up
        sudo sed -i '/zone ""/,/};/d' /etc/bind/named.conf.local # Limpiar basura
        sudo systemctl restart bind9
        echo "$IP_ING" # IMPORTANTE: Esto le dice al main la IP
    else
        echo "INVALID"
    fi
}

# --- 3. DHCP ---
config_dhcp_logic() {
    local ip_fija=$1
    local segmento=$2
    local oct_srv=$3
    local interface="enp0s8"

    local gateway="${segmento}.1"
    local min_ini=$((oct_srv + 1))
    
    read -p "IP Inicial (Mínimo $segmento.$min_ini): " ip_ini
    read -p "IP Final: " ip_fin
    read -p "Lease time: " lease

    sudo sed -i "s/INTERFACESv4=\".*\"/INTERFACESv4=\"$interface\"/" /etc/default/isc-dhcp-server
    sudo bash -c "cat > /etc/dhcp/dhcpd.conf" <<EOF
default-lease-time $lease;
max-lease-time $((lease * 2));
authoritative;
subnet ${segmento}.0 netmask 255.255.255.0 {
  range $ip_ini $ip_fin;
  option routers $gateway;
  option domain-name-servers $ip_fija;
}
EOF
    sudo systemctl restart isc-dhcp-server
    echo "DHCP configurado."
}

# --- 4. DOMINIOS ---
add_dominio_logic() {
    local dom=$1
    local ip_fija=$2
    local zone_file="/etc/bind/db.$dom"

    sudo bash -c "cat > $zone_file" <<EOF
\$TTL 604800
@ IN SOA ns.$dom. admin.$dom. ( 1 604800 86400 2419200 604800 )
@ IN NS ns.$dom.
ns IN A $ip_fija
@  IN A $ip_fija
EOF
    sudo bash -c "echo 'zone \"$dom\" { type master; file \"$zone_file\"; };' >> /etc/bind/named.conf.local"
    sudo systemctl restart bind9
}

del_dominio_logic() {
    local dom=$1
    sudo sed -i "/zone \"$dom\"/d" /etc/bind/named.conf.local
    sudo rm -f "/etc/bind/db.$dom"
    sudo systemctl restart bind9
}