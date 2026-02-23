#!/bin/bash
# --- VARIABLES GLOBALES ---
IP_FIJA=""
INTERFACE="enp0s8"
SEGMENTO=""
OCT_SRV=0

# --- 1. INSTALACIÓN DE INFRAESTRUCTURA ---
instalar_servicios() {
    echo "--- Instalando ISC-DHCP-SERVER y BIND9 ---"
    sudo apt-get update && sudo apt-get install -y isc-dhcp-server bind9 bind9utils
    sudo systemctl enable isc-dhcp-server bind9
    echo "Servicios instalados correctamente."
    read -p "Presiona [r] para volver..."
}

# --- 2. IP FIJA (DNS, SERVER Y DOMINIOS) ---
establecer_ip_fija() {
    echo "--- Configurar IP Fija y Activar DNS ---"
    while true; do
        read -p "Ingrese la IP Fija (ej. 11.11.11.2) o [r]: " IP_ING
        [[ "$IP_ING" == "r" ]] && return
        
        # VALIDACIÓN: Formato IP estricto
        if [[ $IP_ING =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            IP_FIJA=$IP_ING
            SEGMENTO=$(echo $IP_FIJA | cut -d'.' -f1-3)
            OCT_SRV=$(echo $IP_FIJA | cut -d'.' -f4)
            
            sudo ip addr flush dev $INTERFACE
            sudo ip addr add $IP_FIJA/24 dev $INTERFACE
            sudo ip link set $INTERFACE up
            
            limpiar_zonas_basura
            sudo systemctl restart bind9
            echo "IP establecida y DNS reiniciado."
            break
        else 
            echo "ERROR: Formato de IP inválido. Solo números y puntos."
        fi
    done
}

# --- 3. CONFIGURAR DHCP ---
config_dhcp() {
    [[ -z "$IP_FIJA" ]] && { echo "ERROR: Primero establece la IP Fija (Opción 2)."; read -p "Enter..."; return; }
    
    GATEWAY="${SEGMENTO}.1"
    MIN_INI=$((OCT_SRV + 1))
    
    echo "--- Rango DHCP (Gateway: $GATEWAY) ---"
    
    # VALIDACIÓN: IP Inicial (Rango y Formato)
    while true; do
        read -p "IP Inicial (Mínimo $SEGMENTO.$MIN_INI) o [r]: " IP_INI
        [[ "$IP_INI" == "r" ]] && return
        if [[ $IP_INI =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            OCT_INI=$(echo $IP_INI | cut -d'.' -f4)
            if [[ "$(echo $IP_INI | cut -d'.' -f1-3)" == "$SEGMENTO" && $OCT_INI -ge $MIN_INI ]]; then
                break
            fi
        fi
        echo "Error: La IP inicial debe ser mínimo $SEGMENTO.$MIN_INI y del mismo segmento."
    done

    # VALIDACIÓN: IP Final (Debe ser mayor a la inicial)
    while true; do
        read -p "IP Final (ej. $SEGMENTO.254): " IP_FIN
        if [[ $IP_FIN =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            OCT_FIN=$(echo $IP_FIN | cut -d'.' -f4)
            if [[ $OCT_FIN -gt $OCT_INI && $OCT_FIN -le 254 ]]; then
                break
            fi
        fi
        echo "Error: La IP final debe ser mayor a $IP_INI y no exceder .254."
    done

    # VALIDACIÓN: Tiempo de concesión (Solo números positivos)
    while true; do
        read -p "Lease time en segundos (mínimo 60): " LEASE
        if [[ "$LEASE" =~ ^[0-9]+$ ]] && [ "$LEASE" -ge 60 ]; then
            break
        else
            echo "Error: Ingrese un número positivo de segundos (mínimo 60)."
        fi
    done

    # Mantenemos tus comandos intactos de configuración
    sudo sed -i "s/INTERFACESv4=\".*\"/INTERFACESv4=\"$INTERFACE\"/" /etc/default/isc-dhcp-server
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
    sudo systemctl restart isc-dhcp-server
    echo "¡DHCP Activo! Rango: $IP_INI - $IP_FIN."
    read -p "Enter..."
}

# --- 4. GESTIÓN DE DOMINIOS DNS ---
add_dominio() {
    [[ -z "$IP_FIJA" ]] && { echo "Error: IP Fija requerida."; return; }
    limpiar_zonas_basura

    # VALIDACIÓN: Nombre de dominio (Sin caracteres raros)
    while true; do
        read -p "Nombre del dominio o [r]: " DOM
        [[ "$DOM" == "r" ]] && return
        if [[ "$DOM" =~ ^[a-zA-Z0-9][-a-zA-Z0-9.]*\.[a-zA-Z]{2,}$ ]]; then
            break
        else
            echo "Error: Nombre de dominio inválido (ej: aprobar.com). Sin @, # o $."
        fi
    done

    ZONE_FILE="/etc/bind/db.$DOM"
    sudo bash -c "cat > $ZONE_FILE" <<EOF
\$TTL 604800
@ IN SOA ns.$DOM. admin.$DOM. ( 1 604800 86400 2419200 604800 )
@ IN NS ns.$DOM.
ns IN A $IP_FIJA
@  IN A $IP_FIJA
EOF

    sudo bash -c "echo 'zone \"$DOM\" { type master; file \"$ZONE_FILE\"; };' >> /etc/bind/named.conf.local"
    
    if sudo named-checkconf; then
        sudo systemctl restart bind9
        echo "Dominio $DOM creado correctamente."
    else
        echo "Error detectado. Limpiando..."
        limpiar_zonas_basura
        sudo systemctl restart bind9
    fi
    read -p "Presiona Enter..."
}
# --- (El resto de funciones se mantienen iguales) ---
del_dominio() {
    read -p "Ingrese el nombre EXACTO del dominio a borrar: " DOM_DEL
    [[ -z "$DOM_DEL" ]] && return

    # REGRESO A TU LÓGICA ORIGINAL PERO CON ANCLAJE ^
    # El "^zone" asegura que solo borre la línea que EMPIEZA con ese nombre exacto.
    if grep -q "zone \"$DOM_DEL\"" /etc/bind/named.conf.local; then
        echo "Eliminando ÚNICAMENTE $DOM_DEL..."
        
        # EL COMANDO SEGURO:
        # Usamos comillas dobles y el nombre exacto para que no confunda "bola" con "cebola"
        sudo sed -i "/zone \"$DOM_DEL\"/,/};/d" /etc/bind/named.conf.local
        sudo rm -f "/etc/bind/db.$DOM_DEL"
        
        limpiar_zonas_basura
        sudo systemctl restart bind9
        echo "Dominio $DOM_DEL eliminado con éxito."
    else
        echo "El dominio $DOM_DEL no existe."
    fi
    read -p "Presiona [Enter]..."
}
check_status() {
    clear
    echo "=== ESTADO DETALLADO ==="
    echo -n "DHCP: "; systemctl is-active --quiet isc-dhcp-server && echo "ACTIVO" || echo "CAÍDO"
    echo -n "DNS: "; systemctl is-active --quiet bind9 && echo "ACTIVO" || echo "CAÍDO"
    echo -e "\nDominios en memoria:"
    sudo named-checkconf -z | grep "loaded"
    read -p "Enter..."
}

limpiar_zonas_basura() {
    sudo sed -i '/zone ""/,/};/d' /etc/bind/named.conf.local
}

while true; do
    clear
    echo "IP SRV (DNS/DOM): ${IP_FIJA:-PENDIENTE}"
    echo "1. Instalar DHCP/DNS   2. IP Fija (Server/DNS)"
    echo "3. Configurar DHCP     4. Añadir Dominio"
    echo "5. Eliminar Dominio    6. Listar Dominios"
    echo "7. Check Status        8. Ver Red        9. Salir"
    read -p "Seleccione: " op
    case $op in
        1) instalar_servicios ;; 2) establecer_ip_fija ;; 3) config_dhcp ;;
        4) add_dominio ;; 5) del_dominio ;; 6) grep "zone" /etc/bind/named.conf.local | cut -d'"' -f2; read -p "..." ;;
        7) check_status ;; 8) ip addr; read -p "..." ;; 9) exit 0 ;;
    esac
done