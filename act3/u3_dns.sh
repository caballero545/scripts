#!/bin/bash

# --- VARIABLES ---
IP_FIJA=""
INTERFACE="enp0s8"
SEGMENTO=""

# --- 1. INSTALACIÓN ---
instalar_todo() {
    echo "--- Instalando DHCP y DNS (BIND9) ---"
    sudo apt-get update && sudo apt-get install -y isc-dhcp-server bind9 bind9utils
    sudo systemctl enable isc-dhcp-server bind9
    echo "Servicios instalados."
    read -p "Presiona [r] para volver..."
}

# --- 2. IP FIJA (EL CORAZÓN DEL SCRIPT) ---
set_ip_fija() {
    echo "--- Configurar IP del Servidor ---"
    while true; do
        read -p "Ingrese IP Fija (ej. 11.11.11.2) o [r]: " IP_ING
        [[ "$IP_ING" == "r" ]] && return
        if [[ $IP_ING =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            IP_FIJA=$IP_ING
            SEGMENTO=$(echo $IP_FIJA | cut -d'.' -f1-3)
            OCTETO_SRV=$(echo $IP_FIJA | cut -d'.' -f4)
            sudo ip addr flush dev $INTERFACE
            sudo ip addr add $IP_FIJA/24 dev $INTERFACE
            sudo ip link set $INTERFACE up
            break
        else echo "IP inválida."; fi
    done
}

# --- 3. CONFIGURAR DHCP ---
config_dhcp() {
    [[ -z "$IP_FIJA" ]] && { echo "ERROR: Primero pon la IP Fija."; read -p "Enter..."; return; }
    
    GATEWAY="${SEGMENTO}.1"
    MIN_INI=$((OCTETO_SRV + 1))
    
    echo "--- Rango DHCP (Segmento $SEGMENTO.x) ---"
    read -p "IP Inicial (Mínimo $SEGMENTO.$MIN_INI): " IP_INI
    read -p "IP Final: " IP_FIN
    read -p "Lease (seg): " LEASE

    sudo bash -c "cat > /etc/dhcp/dhcpd.conf" <<EOF
default-lease-time $LEASE;
max-lease-time $((LEASE * 2));
authoritative;
subnet ${SEGMENTO}.0 netmask 255.255.255.0 {
  range $IP_INI $IP_FIN;
  option routers $GATEWAY;
  option domain-name-servers $IP_FIJA;
}
EOF
    sudo sed -i "s/INTERFACESv4=\".*\"/INTERFACESv4=\"$INTERFACE\"/" /etc/default/isc-dhcp-server
    sudo systemctl restart isc-dhcp-server
    echo "DHCP Activo."
    read -p "Enter..."
}

# --- 4. GESTIÓN DE DOMINIOS (DNS) ---
add_dominio() {
    [[ -z "$IP_FIJA" ]] && { echo "Error: Falta IP Fija."; return; }
    read -p "Nombre del dominio (ej. hola.com) o [r]: " DOM
    [[ "$DOM" == "r" || -z "$DOM" ]] && return

    ZONE_FILE="/etc/bind/db.$DOM"
    sudo bash -c "cat > $ZONE_FILE" <<EOF
\$TTL 604800
@ IN SOA ns.$DOM. admin.$DOM. ( 1 604800 86400 2419200 604800 )
@ IN NS ns.$DOM.
ns IN A $IP_FIJA
@  IN A $IP_FIJA
EOF
    sudo bash -c "echo 'zone \"$DOM\" { type master; file \"$ZONE_FILE\"; };' >> /etc/bind/named.conf.local"
    sudo systemctl restart bind9
    echo "Dominio $DOM añadido."
}

delete_dominio() {
    read -p "Dominio a ELIMINAR o [r]: " DOM_DEL
    [[ "$DOM_DEL" == "r" || -z "$DOM_DEL" ]] && return
    
    if grep -q "zone \"$DOM_DEL\"" /etc/bind/named.conf.local; then
        # Borrado quirúrgico
        sudo sed -i "/zone \"$DOM_DEL\"/,/};/d" /etc/bind/named.conf.local
        sudo rm -f "/etc/bind/db.$DOM_DEL"
        sudo systemctl restart bind9
        echo "Dominio eliminado."
    else
        echo "No existe."
    fi
    read -p "Enter..."
}

listar_dominios() {
    echo "--- Dominios en BIND9 ---"
    grep "zone" /etc/bind/named.conf.local | cut -d'"' -f2
    read -p "Enter..."
}

# --- 5. CHECK STATUS ---
check_status() {
    echo "=== STATUS DHCP ==="
    sudo systemctl is-active isc-dhcp-server
    echo "=== STATUS DNS (BIND9) ==="
    sudo systemctl is-active bind9
    echo "=== ZONAS CARGADAS ==="
    sudo named-checkconf -z | grep "loaded"
    read -p "Enter..."
}

# --- MENU ---
while true; do
    clear
    echo "IP SRV: $IP_FIJA"
    echo "1. Instalar  2. IP Fija  3. Config DHCP"
    echo "4. Add Dom   5. Del Dom   6. Listar Dom"
    echo "7. Status    8. Ver Red   9. Salir"
    read -p "Opcion: " op
    case $op in
        1) instalar_todo ;; 2) set_ip_fija ;; 3) config_dhcp ;;
        4) add_dominio ;; 5) delete_dominio ;; 6) listar_dominios ;;
        7) check_status ;; 8) ip addr; read -p "..." ;; 9) exit 0 ;;
    esac
done