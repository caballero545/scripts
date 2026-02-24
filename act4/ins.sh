#!/bin/bash
# dns_functions.sh - Lógica modular para DHCP y DNS
# --- INSTALACIÓN ---
instalar_servicios() {
    echo "--- Instalando ISC-DHCP-SERVER y BIND9 ---"
    sudo apt-get update && sudo apt-get install -y isc-dhcp-server bind9 bind9utils openssh-server
    sudo systemctl enable --now ssh
    sudo systemctl enable isc-dhcp-server bind9
}

# --- RED ---
establecer_ip_fija() {
    local interface=$1
    read -p "Ingrese la IP Fija: " IP_ING
    if [[ $IP_ING =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        sudo ip addr flush dev $interface
        sudo ip addr add $IP_ING/24 dev $interface
        sudo ip link set $interface up
        echo "$IP_ING" # Retornamos la IP para el script principal
    else
        echo "ERROR"
    fi
}

# --- GESTIÓN DE DOMINIOS ---
limpiar_zonas_basura() {
    sudo sed -i '/zone ""/,/};/d' /etc/bind/named.conf.local
}

validar_y_añadir_dns() {
    local dom=$1
    local ip=$2
    # Uso de grep para validar existencia
    if grep -q "zone \"$dom\"" /etc/bind/named.conf.local; then
        return 1 # Ya existe
    fi
    
    # Crear archivo de zona
    local zone_file="/etc/bind/db.$dom"
    sudo bash -c "cat > $zone_file" <<EOF
\$TTL 604800
@ IN SOA ns.$dom. admin.$dom. ( 1 604800 86400 2419200 604800 )
@ IN NS ns.$dom.
ns IN A $ip
@  IN A $ip
EOF
    # Añadir al config en una sola línea para borrado quirúrgico
    sudo bash -c "echo 'zone \"$dom\" { type master; file \"$zone_file\"; };' >> /etc/bind/named.conf.local"
    return 0
}

borrar_dominio_quirurgico() {
    local dom=$1
    # Borra SOLO la línea exacta del dominio
    sudo sed -i "/zone \"$dom\"/d" /etc/bind/named.conf.local
    sudo rm -f "/etc/bind/db.$dom"
}