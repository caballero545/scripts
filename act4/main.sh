#!/bin/bash
# main.sh
source ./ins.sh

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
        
        2) 
           # Capturamos la salida de la función para llenar las variables
           RESP=$(establecer_ip_fija_logic)
           if [ "$RESP" != "ERROR" ]; then
               IP_FIJA=$RESP
               SEGMENTO=$(echo $IP_FIJA | cut -d'.' -f1-3)
               OCT_SRV=$(echo $IP_FIJA | cut -d'.' -f4)
           fi ;;

        3) 
           # Pasamos las variables a la función
           config_dhcp_logic "$IP_FIJA" "$SEGMENTO" "$OCT_SRV" ;;

        4) 
           [[ -z "$IP_FIJA" ]] && { echo "Fija la IP primero"; sleep 2; continue; }
           read -p "Nombre dominio: " DOM
           # Pasamos el nombre y la IP
           add_dominio_logic "$DOM" "$IP_FIJA"
           [[ $? -eq 0 ]] && echo "Éxito" || echo "Error"
           sleep 2 ;;

        5) 
           read -p "Dominio a borrar: " DOM_DEL
           if del_dominio_logic "$DOM_DEL"; then
               echo "Borrado correctamente."
           else
               echo "Error: Ese dominio NO existe."
           fi
           sleep 2 ;;

        6) grep "zone" /etc/bind/named.conf.local | cut -d'"' -f2; read -p "..." ;;
        
        7) check_status_logic "$IP_FIJA" ;;

        8) exit 0 ;;
    esac
done