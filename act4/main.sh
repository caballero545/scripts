#!/bin/bash
# main.sh - Interfaz de usuario
source ./ins.sh

INTERFACE="enp0s3"
IP_FIJA=""

while true; do
    clear
    echo "ADMINISTRACIÓN REMOTA - IP SRV: ${IP_FIJA:-PENDIENTE}"
    echo "1. Instalar Infraestructura   2. Configurar IP Fija"
    echo "3. Añadir Dominio             4. Eliminar Dominio"
    echo "5. Ver Status                 6. Salir"
    read -p "Opción: " op

    case $op in
        1) instalar_servicios ;;
        2) 
            RES=$(establecer_ip_fija "$INTERFACE")
            [[ "$RES" != "ERROR" ]] && IP_FIJA=$RES ;;
        3)
            [[ -z "$IP_FIJA" ]] && echo "Primero fija la IP" && sleep 2 && continue
            read -p "Nombre dominio: " DOM
            if validar_y_añadir_dns "$DOM" "$IP_FIJA"; then
                sudo systemctl restart bind9
                echo "Dominio creado."
            else
                echo "Error: El dominio ya existe."
            fi
            read ;;
        4)
            read -p "Nombre a borrar: " DOM
            borrar_dominio_quirurgico "$DOM"
            sudo systemctl restart bind9
            echo "Eliminado."
            read ;;
        5) 
            sudo named-checkconf -z | grep "loaded"
            read ;;
        6) exit 0 ;;
    esac
done