#!/bin/bash
# main.sh - Interfaz de usuario
source ./ins.sh

INTERFACE="enp0s3"
IP_FIJA=""

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