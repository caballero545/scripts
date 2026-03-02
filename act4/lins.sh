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
    read -p "Ingrese IP Fija: " IP_ING
    if [[ $IP_ING =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        sudo ip addr flush dev $interface
        sudo ip addr add $IP_ING/24 dev $interface
        sudo ip link set $interface up
        # Limpiamos zonas vacías que causan errores al arrancar
        sudo sed -i '/zone ""/,/};/d' /etc/bind/named.conf.local
        echo "$IP_ING"
    else
        echo "ERROR"
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
    
    # VALIDACIÓN: Checar si ya existe para no duplicar basura
    if grep -q "zone \"$dom\"" /etc/bind/named.conf.local; then
        return 1 # Ya existe, error.
    fi

    local zone_file="/etc/bind/db.$dom"
    sudo bash -c "cat > $zone_file" <<EOF
\$TTL 604800
@ IN SOA ns.$dom. admin.$dom. ( 1 604800 86400 2419200 604800 )
@ IN NS ns.$dom.
ns IN A $ip_fija
@  IN A $ip_fija
EOF
    sudo bash -c "echo 'zone \"$dom\" { type master; file \"$zone_file\"; };' >> /etc/bind/named.conf.local"
    
    # VALIDACIÓN DE SINTAXIS
    if ! sudo named-checkconf; then
        sudo sed -i "/zone \"$dom\"/d" /etc/bind/named.conf.local
        return 2 # Fallo de sintaxis
    fi
    sudo systemctl restart bind9
    return 0
}

del_dominio_logic() {
    local dom=$1
    # AQUÍ ESTÁ EL CAMBIO: Grep verifica si existe antes de borrar
    if ! grep -q "zone \"$dom\"" /etc/bind/named.conf.local; then
        return 1 # Si no existe, manda error al main
    fi
    sudo sed -i "/zone \"$dom\"/d" /etc/bind/named.conf.local
    sudo rm -f "/etc/bind/db.$dom"
    sudo systemctl restart bind9
    return 0
}
check_status_logic() {
    local ip_actual=$1
    clear
    echo "=========================================="
    echo "      ESTADO DEL SISTEMA (REMOTO)"
    echo "=========================================="
    
    # Verificación de Procesos
    echo -n "Servicio DHCP: "
    systemctl is-active --quiet isc-dhcp-server && echo -e "\e[32mACTIVO\e[0m" || echo -e "\e[31mCAÍDO\e[0m"
    
    echo -n "Servicio DNS (BIND9): "
    systemctl is-active --quiet bind9 && echo -e "\e[32mACTIVO\e[0m" || echo -e "\e[31mCAÍDO\e[0m"

    # Verificación de Zonas cargadas
    echo -e "\n--- Dominios en Memoria ---"
    local zonas=$(sudo named-checkconf -z | grep "loaded")
    if [ -z "$zonas" ]; then
        echo -e "\e[31m[!] No hay dominios activos o hay error de sintaxis.\e[0m"
    else
        echo -e "\e[32m$zonas\e[0m"
    fi

    echo -e "\n--- Configuración de Red ---"
    echo "IP Fija configurada en Script: ${ip_actual:-Ninguna}"
    ip addr show enp0s8 | grep "inet " || echo "Interfaz enp0s8 sin IP activa."
    echo "=========================================="
    read -p "Presiona Enter para volver..."
}