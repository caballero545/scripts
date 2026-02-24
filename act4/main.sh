#!/bin/bash
source ./ins.sh

# Credenciales y variables
INTERFACE="enp0s3"

echo "--- MÓDULO DE ADMINISTRACIÓN REMOTA ---"
echo "1) Instalar Infraestructura"
echo "2) Configurar IP Fija"
read -p "Seleccione: " op

case $op in
    1) instalar_paquetes ;;
    2) 
        read -p "IP deseada: " IP
        configurar_interfaz "$IP" "$INTERFACE"
        ;;
esac