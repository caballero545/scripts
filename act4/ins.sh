#!/bin/bash
# dns_functions.sh - Lógica modular para DHCP y DNS
# --- INSTALACIÓN ---
instalar_servicios() {-------1
    echo "--- Instalando ISC-DHCP-SERVER y BIND9 ---"
    sudo apt-get update && sudo apt-get install -y isc-dhcp-server bind9 bind9utils openssh-server
    sudo systemctl enable --now ssh
    sudo systemctl enable isc-dhcp-server bind9
}

# --- RED ---
establecer_ip_fija() {//----2
    echo "--- Configurar IP Fija y Activar DNS ---"
    while true; do
        read -p "Ingrese la IP Fija (ej. 11.11.11.2) o [r]: " IP_ING
        [[ "$IP_ING" == "r" ]] && return
        
        if [[ $IP_ING =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            IP_FIJA=$IP_ING
            SEGMENTO=$(echo $IP_FIJA | cut -d'.' -f1-3)
            OCT_SRV=$(echo $IP_FIJA | cut -d'.' -f4)
            
            sudo ip addr flush dev $INTERFACE
            sudo ip addr add $IP_FIJA/24 dev $INTERFACE
            sudo ip link set $INTERFACE up
            
            # --- CURAR Y ACTIVAR DNS AQUÍ ---
            limpiar_zonas_basura
            sudo systemctl restart bind9
            echo "IP establecida y DNS reiniciado."
            break
        else echo "IP inválida."; fi
    done
}
# --- GESTIÓN DE DOMINIOS ---
limpiar_zonas_basura() {---usable
    sudo sed -i '/zone ""/,/};/d' /etc/bind/named.conf.local
}
config_dhcp() {-------3
    [[ -z "$IP_FIJA" ]] && { echo "ERROR: Primero establece la IP Fija (Opción 2)."; read -p "Enter..."; return; }
    
    GATEWAY="${SEGMENTO}.1"
    MIN_INI=$((OCT_SRV + 1)) # Validación: IP inicial >= IP_SRV + 1
    
    echo "--- Rango DHCP (Gateway: $GATEWAY) ---"
    while true; do
        read -p "IP Inicial (Mínimo $SEGMENTO.$MIN_INI) o [r]: " IP_INI
        [[ "$IP_INI" == "r" ]] && return
        OCT_INI=$(echo $IP_INI | cut -d'.' -f4)
        if [[ "$(echo $IP_INI | cut -d'.' -f1-3)" == "$SEGMENTO" && $OCT_INI -ge $MIN_INI ]]; then
            break
        else
            echo "Error: La IP inicial debe ser mínimo $SEGMENTO.$MIN_INI."
        fi
    done

    read -p "IP Final (ej. $SEGMENTO.254): " IP_FIN
    read -p "Lease time (seg): " LEASE

    # Configuración de archivos
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
    echo "¡DHCP Activo! Gateway .1 y DNS en $IP_FIJA."
    read -p "Enter..."
}
add_dominio() {------4
    [[ -z "$IP_FIJA" ]] && { echo "Error: IP Fija requerida."; return; }
    
    # Primero: Limpiamos cualquier error previo
    limpiar_zonas_basura

    read -p "Nombre del dominio o [r]: " DOM
    [[ "$DOM" == "r" || -z "$DOM" ]] && return

    # Creamos la zona (esto ya lo tienes)
    ZONE_FILE="/etc/bind/db.$DOM"
    sudo bash -c "cat > $ZONE_FILE" <<EOF
\$TTL 604800
@ IN SOA ns.$DOM. admin.$DOM. ( 1 604800 86400 2419200 604800 )
@ IN NS ns.$DOM.
ns IN A $IP_FIJA
@  IN A $IP_FIJA
EOF

    # Añadimos la zona al config
    limpiar_zonas_basura
    sudo bash -c "echo 'zone \"$DOM\" { type master; file \"$ZONE_FILE\"; };' >> /etc/bind/named.conf.local"
    
    # Reinicio con validación
    if sudo named-checkconf; then
        sudo systemctl restart bind9
        echo "Dominio $DOM creado y DNS levantado."
    else
        echo "Error detectado. Limpiando configuración..."
        limpiar_zonas_basura
        sudo systemctl restart bind9
    fi
    read -p "Presiona Enter..."
}
del_dominio() {-----5
    read -p "Ingrese el nombre EXACTO del dominio a borrar: " DOM_DEL
    [[ -z "$DOM_DEL" ]] && return

    # Verificamos si existe el dominio
    if grep -q "zone \"$DOM_DEL\"" /etc/bind/named.conf.local; then
        echo "Borrando ÚNICAMENTE: $DOM_DEL..."
        
        # EXPLICACIÓN TÉCNICA:
        # Tu comando add_dominio mete la zona en una sola línea: zone "dom" { ... };
        # Por lo tanto, borrar "desde-hasta" es lo que causa que se lleve otros.
        # Este comando busca la línea que contiene exactamente zone "tu-dominio" y BORRA SOLO ESA LÍNEA.
        sudo sed -i "/zone \"$DOM_DEL\"/d" /etc/bind/named.conf.local
        
        # Borramos el archivo db asociado
        sudo rm -f "/etc/bind/db.$DOM_DEL"
        
        limpiar_zonas_basura
        sudo systemctl restart bind9
        echo "Éxito: Dominio '$DOM_DEL' eliminado. Los demás están intactos."
    else
        echo "El dominio '$DOM_DEL' no existe."
    fi
    read -p "Presiona [Enter] para continuar..."
}
check_status() {------7
    clear
    echo "=========================================="
    echo "       ESTADO DETALLADO DEL SISTEMA"
    echo "=========================================="
    
    # 1. Estado de los Procesos
    echo -n "Servicio DHCP: "
    systemctl is-active --quiet isc-dhcp-server && echo -e "\e[32mACTIVO\e[0m" || echo -e "\e[31mCAÍDO\e[0m"
    
    echo -n "Servicio DNS (BIND9): "
    systemctl is-active --quiet bind9 && echo -e "\e[32mACTIVO\e[0m" || echo -e "\e[31mCAÍDO\e[0m"
    
    # 2. Verificación de Zonas (Carga real)
    echo -e "\n--- Dominios Cargados en Memoria ---"
    ZONAS_LOADED=$(sudo named-checkconf -z | grep "loaded")
    
    if [ -z "$ZONAS_LOADED" ]; then
        echo -e "\e[31m[!] No hay dominios cargados. Posibles errores de sintaxis:\e[0m"
        # Mostramos el error real sin filtrar para que veas qué falló
        sudo named-checkconf -z
    else
        echo -e "\e[32m$ZONAS_LOADED\e[0m"
    fi
    
    # 3. IP Fija Actual
    echo -e "\n--- Configuración de Red ---"
    echo "IP Fija del Servidor: ${IP_FIJA:-No configurada}"
    
    echo "=========================================="
    read -p "Presiona [Enter] para volver al menú..."
}