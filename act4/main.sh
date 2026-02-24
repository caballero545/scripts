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
        
        2) 
           # Capturamos la respuesta de la función
           RESP=$(establecer_ip_fija_logic)
           if [[ "$RESP" != "CANCEL" && "$RESP" != "INVALID" ]]; then
               IP_FIJA=$RESP
               SEGMENTO=$(echo $IP_FIJA | cut -d'.' -f1-3)
               OCT_SRV=$(echo $IP_FIJA | cut -d'.' -f4)
               echo "IP Guardada: $IP_FIJA"
           else
               echo "Error en IP o Cancelado"
           fi
           sleep 2 ;;

        3) 
           if [[ -z "$IP_FIJA" ]]; then echo "Error: Fija la IP primero"; sleep 2; continue; fi
           config_dhcp_logic "$IP_FIJA" "$SEGMENTO" "$OCT_SRV"
           read -p "Enter..." ;;

        4) 
           if [[ -z "$IP_FIJA" ]]; then echo "Error: Fija la IP primero"; sleep 2; continue; fi
           read -p "Nombre del dominio: " DOM
           add_dominio_logic "$DOM" "$IP_FIJA"
           echo "Dominio $DOM creado."
           sleep 2 ;;

        5)
           read -p "Dominio a borrar: " DOM_DEL
           del_dominio_logic "$DOM_DEL"
           echo "Borrado."
           sleep 2 ;;

        6) grep "zone" /etc/bind/named.conf.local | cut -d'"' -f2; read -p "..." ;;
        
        7) sudo named-checkconf -z | grep "loaded"; read -p "Enter..." ;;

        8) exit 0 ;;
    esac
done