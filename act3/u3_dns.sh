#!/bin/bash
# =====================================================================
# SCRIPT DE ADMINISTRACIÓN INTEGRAL: DHCP & DNS (VERSIÓN PROFESIONAL)
# =====================================================================

# --- VARIABLES GLOBALES ---
IP_FIJA=""
INTERFACE="enp0s8"
SEGMENTO=""

# --- FUNCIONES DE VALIDACIÓN ---

# 1. Validación de IP para el SERVIDOR
# Prohibidas: 0.0.0.0, 255.255.255.255, 127.0.0.0, 127.0.0.1
validar_ip_servidor() {
    local ip=$1
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 1; fi
    
    if [[ "$ip" == "0.0.0.0" ]] || [[ "$ip" == "255.255.255.255" ]] || \
       [[ "$ip" == "127.0.0.0" ]] || [[ "$ip" == "127.0.0.1" ]]; then
        echo -e "\e[31m[ERROR] La IP $ip está prohibida para el servidor.\e[0m"
        return 1
    fi
    return 0
}

# 2. Validación de IP para el DNS
# Prohibidas: 255.255.255.255, 1.0.0.0
validar_ip_dns() {
    local ip=$1
    [[ -z "$ip" ]] && return 0 # Si está vacío es válido (opcional)
    if [[ ! $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 1; fi

    if [[ "$ip" == "255.255.255.255" ]] || [[ "$ip" == "1.0.0.0" ]]; then
        echo -e "\e[31m[ERROR] La IP $ip está prohibida como servidor DNS.\e[0m"
        return 1
    fi
    return 0
}

# 3. Validación de Máscara
validar_mask() { [[ $1 =~ ^(255|254|252|248|240|224|192|128|0)\.(255|254|252|248|240|224|192|128|0)\.(255|254|252|248|240|224|192|128|0)\.(255|254|252|248|240|224|192|128|0)$ ]]; }

# 4. Validación de Tiempo (No negativos)
validar_tiempo() {
    if [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -gt 0 ]; then return 0; else return 1; fi
}

# --- UTILIDADES ---
limpiar_zonas_basura() { sudo sed -i '/zone ""/,/};/d' /etc/bind/named.conf.local; }

# --- 1. INSTALACIÓN ---
instalar_servicios() {
    echo -e "\n[+] Instalando ISC-DHCP-SERVER y BIND9..."
    sudo apt-get update && sudo apt-get install -y isc-dhcp-server bind9 bind9utils
    sudo systemctl enable isc-dhcp-server bind9
    echo "[!] Servicios instalados correctamente."
    read -p "Presiona Enter para continuar..."
}

# --- 2. CONFIGURACIÓN DE RED Y DHCP (Lógica de Rango Desplazado) ---
configurar_sistema_principal() {
    echo -e "\n--- CONFIGURACIÓN DE RED Y RANGO DHCP ---"
    
    # Rango inicial (Será la IP Fija del Server)
    while true; do
        read -p "Ingrese inicio de rango (ej. 10.10.10.0): " R_INI
        if validar_ip_servidor "$R_INI"; then break; fi
    done

    # Rango final
    while true; do
        read -p "Ingrese fin de rango (ej. 10.10.10.20): " R_FIN
        if validar_ip_servidor "$R_FIN"; then break; fi
    done

    # Lógica de asignación: Server toma la primera IP
    IP_FIJA=$R_INI
    SEGMENTO=$(echo $IP_FIJA | cut -d'.' -f1-3)
    
    # Lógica de desplazamiento +1 para el DHCP
    OCT_INI=$(echo $R_INI | cut -d'.' -f4)
    OCT_FIN=$(echo $R_FIN | cut -d'.' -f4)
    DHCP_START="${SEGMENTO}.$((OCT_INI + 1))"
    DHCP_END="${SEGMENTO}.$((OCT_FIN + 1))"

    # Máscara
    while true; do
        read -p "Máscara de red [Enter para 255.255.255.0]: " MASK
        [[ -z "$MASK" ]] && MASK="255.255.255.0"
        if validar_mask "$MASK"; then break; else echo "Máscara inválida."; fi
    done

    # Puerta de Enlace (Opcional)
    read -p "Puerta de enlace (Gateway) [Enter para vacío]: " GW

    # DNS Primario con validación estricta
    while true; do
        read -p "DNS Primario [Enter para vacío]: " DNS_1
        if validar_ip_dns "$DNS_1"; then break; fi
    done

    # DNS Secundario con validación estricta
    while true; do
        read -p "DNS Secundario [Enter para vacío]: " DNS_2
        if validar_ip_dns "$DNS_2"; then break; fi
    done

    # Tiempo de escucha (Validación no negativos)
    while true; do
        read -p "Tiempo de escucha (segundos): " LEASE
        if validar_tiempo "$LEASE"; then break; else echo "Error: Ingrese un número positivo."; fi
    done

    # --- APLICAR CONFIGURACIÓN AL SISTEMA ---
    echo "[*] Configurando interfaz $INTERFACE con IP $IP_FIJA..."
    sudo ip addr flush dev $INTERFACE
    sudo ip addr add $IP_FIJA/24 dev $INTERFACE
    sudo ip link set $INTERFACE up

    # --- CONSTRUIR ARCHIVO DHCPD.CONF ---
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

    # Reiniciar servicios
    sudo sed -i "s/INTERFACESv4=\".*\"/INTERFACESv4=\"$INTERFACE\"/" /etc/default/isc-dhcp-server
    limpiar_zonas_basura
    sudo systemctl restart bind9
    sudo systemctl restart isc-dhcp-server
    
    echo -e "\n[!] SISTEMA CONFIGURADO:"
    echo "    - IP Servidor: $IP_FIJA"
    echo "    - Rango DHCP: $DHCP_START - $DHCP_END"
    read -p "Presiona Enter..."
}

# --- 3. GESTIÓN DE DOMINIOS DNS ---
add_dominio() {
    [[ -z "$IP_FIJA" ]] && { echo "Error: Configure la red primero."; sleep 2; return; }
    read -p "Nombre del dominio (ej. miweb.lan): " DOM
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
    
    if sudo named-checkconf; then
        sudo systemctl restart bind9
        echo "Dominio '$DOM' activado correctamente."
    else
        echo "Error en configuración. Revirtiendo..."
        sudo sed -i "/zone \"$DOM\"/d" /etc/bind/named.conf.local
        sudo rm -f $ZONE_FILE
    fi
    read -p "Enter..."
}

del_dominio() {
    read -p "Dominio a eliminar: " DOM_DEL
    if grep -q "zone \"$DOM_DEL\"" /etc/bind/named.conf.local; then
        sudo sed -i "/zone \"$DOM_DEL\"/d" /etc/bind/named.conf.local
        sudo rm -f "/etc/bind/db.$DOM_DEL"
        sudo systemctl restart bind9
        echo "Dominio eliminado."
    else
        echo "No existe el dominio."
    fi
    read -p "Enter..."
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
    echo "6. Status del Sistema"
    echo "7. Salir"
    echo "-----------------------------------------------"
    read -p "Opción: " op
    case $op in
        1) instalar_servicios ;;
        2) configurar_sistema_principal ;;
        3) add_dominio ;;
        4) del_dominio ;;
        5) echo -e "\n--- Dominios Activos ---"
           grep "zone" /etc/bind/named.conf.local | cut -d'"' -f2
           read -p "..." ;;
        6) clear; echo "--- STATUS ---"
           systemctl is-active isc-dhcp-server bind9
           ip addr show $INTERFACE | grep "inet "
           read -p "Enter..." ;;
        7) exit 0 ;;
    esac
done