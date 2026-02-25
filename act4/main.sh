#!/bin/bash
# main.sh
source ./ins.sh

# Variables que el MAIN recordará
IP_FIJA=""
SEGMENTO=""
OCT_SRV=""

while true; do
    clear
    echo "=== ADMIN REMOTO (IP ACTUAL: ${IP_FIJA:-PENDIENTE}) ==="
    echo "1. Instalar Todo       2. IP Fija (Server)"
    echo "3. Configurar DHCP     4. Añadir Dominio"
    echo "5. Eliminar Dominio    6. Listar Dominios"
    echo "7. Status              8. Salir"
    read -p "Seleccione: " op

    case $op in
        1) instalar_servicios ;;
        
        2) establecer_ip_fija_logic ;;

        3) config_dhcp_logic ;;

        4) add_dominio_logic ;;

        5) del_dominio_logic ;;

        6) grep "zone" /etc/bind/named.conf.local | cut -d'"' -f2; read -p "..." ;;
        
        7) check_status_logic ;;

        8) exit 0 ;;
    esac
done