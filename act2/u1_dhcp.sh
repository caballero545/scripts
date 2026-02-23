#!/bin/bash

# --- FUNCION 1: INSTALAR/VERIFICAR ROL DHCP ---
dwnld_updt_dhcp() {
    if ! dpkg -l | grep -q isc-dhcp-server; then
        echo "--- Instalando isc-dhcp-server ---"
        sudo apt-get update && sudo apt-get install -y isc-dhcp-server
    else
        echo "El servicio DHCP ya esta instalado."
        read -p "Desea actualizar el servicio? (s/n): " r
        if [[ "$r" =~ ^[Ss]$ ]]; then
            sudo apt-get update && sudo apt-get install --only-upgrade -y isc-dhcp-server
        fi
    fi
    read -p "Presiona [Enter] para volver al menu..."
}

# --- FUNCION 2: CONFIGURAR PARAMETROS ---
configurar_rango_dhcp() {
    validar_ip() {
        local ip=$1
        if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            return 0
        fi
        return 1
    }

    echo "--- Configuracion de Parametros DHCP ---"
    while true; do
        read -p "Ingrese la IP Inicial (ej. 88.88.88.2): " IP_INI
        if validar_ip "$IP_INI"; then
            SEGMENTO=$(echo $IP_INI | cut -d'.' -f1-3)
            break
        fi
        echo "Error: Formato de IP invalido."
    done

    while true; do
        read -p "Ingrese la IP Final (ej. 88.88.88.10): " IP_FIN
        SEG_FIN=$(echo $IP_FIN | cut -d'.' -f1-3)
        if validar_ip "$IP_FIN" && [ "$SEGMENTO" == "$SEG_FIN" ]; then
            break
        fi
        echo "Error: La IP debe pertenecer a la red $SEGMENTO.x"
    done

    read -p "Tiempo de concesion en segundos (ej. 600): " LEASE_TIME
    
    # --- APLICACION AUTOMATICA ---
    INTERFACE="enp0s8"
    IP_SRV="${SEGMENTO}.1"

    echo "Limpiando interfaz $INTERFACE y aplicando IP $IP_SRV..."
    sudo ip addr flush dev $INTERFACE
    sudo ip addr add $IP_SRV/24 dev $INTERFACE
    sudo ip link set $INTERFACE up

    # Configurar interfaz de escucha
    sudo sed -i "s/INTERFACESv4=\".*\"/INTERFACESv4=\"$INTERFACE\"/" /etc/default/isc-dhcp-server

    # Escribir archivo de configuracion
    sudo bash -c "cat > /etc/dhcp/dhcpd.conf" <<EOF
option domain-name "red.local";
default-lease-time $LEASE_TIME;
max-lease-time $((LEASE_TIME * 2));
authoritative;

subnet ${SEGMENTO}.0 netmask 255.255.255.0 {
  range $IP_INI $IP_FIN;
  option routers $IP_SRV;
  option subnet-mask 255.255.255.0;
}
EOF

    sudo systemctl restart isc-dhcp-server
    echo "¡SERVIDOR DHCP LINUX ACTIVO!"
    read -p "Presiona [Enter] para continuar..."
}

# --- FUNCION 3: MONITOREAR ---
monitorear_dhcp() {
    clear
    echo "=== ESTADO DEL SERVIDOR DHCP ==="
    sudo systemctl status isc-dhcp-server | grep "Active:"
    echo -e "\n--- Equipos Conectados (Leases) ---"
    if [ -f /var/lib/dhcp/dhcpd.leases ]; then
        # Muestra IP y nombre de host de los clientes conectados
        grep -E "lease|hostname" /var/lib/dhcp/dhcpd.leases | sort | uniq
    else
        echo "No hay registros de clientes todavia."
    fi
    read -p "Presiona [Enter] para volver..."
}

# --- FUNCION 4: VER RED (IFCONFIG) ---
ver_red() {
    clear
    echo "=== ESTADO DE RED ACTUAL ==="
    ip addr show | grep -E "eth|enp|inet "
    read -p "Presiona [Enter] para volver..."
}

# --- MENU PRINCIPAL ---
while true; do
    clear
    echo "------------------------------------------"
    echo "      MENU DHCP LINUX (SERVER)"
    echo "------------------------------------------"
    echo "1. Instalar/Actualizar Servidor"
    echo "2. Configurar y Activar Rango"
    echo "3. Monitorear Clientes"
    echo "4. Ver Estado de Red (ip addr)"
    echo "5. Salir"
    echo "------------------------------------------"
    read -p "Seleccione una opcion: " op
    case $op in
        1) dwnld_updt_dhcp ;;
        2) configurar_rango_dhcp ;;
        3) monitorear_dhcp ;;
        4) ver_red ;;
        5) exit 0 ;;
        *) echo "Opcion no valida." ; sleep 2 ;;
    esac
done