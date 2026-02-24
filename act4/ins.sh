#!/bin/bash
# funciones_red.sh

instalar_paquetes() {
    echo "Instalando BIND9 y DHCP..."
    sudo apt-get update && sudo apt-get install -y isc-dhcp-server bind9 bind9utils
    sudo systemctl enable ssh # Asegura SSH para la práctica
}

configurar_interfaz() {
    local ip=$1
    local interface=$2
    echo "Configurando IP $ip en $interface..."
    sudo ip addr flush dev "$interface"
    sudo ip addr add "$ip/24" dev "$interface"
    sudo ip link set "$interface" up
}

# Usa grep para verificar si una zona ya existe antes de añadirla
validar_zona() {
    local dom=$1
    if grep -q "zone \"$dom\"" /etc/bind/named.conf.local; then
        return 0 # Existe
    else
        return 1 # No existe
    fi
}