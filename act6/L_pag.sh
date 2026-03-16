#!/bin/bash
# ==========================================================
# MAIN SCRIPT: provisioner_linux.sh
# ==========================================================

# Cargar el módulo de funciones
if [[ -f "./Lhttp.sh" ]]; then
    source ./http_functions.sh
else
    echo "Error: No se encontró http_functions.sh"
    exit 1
fi

# Asegurar privilegios de root
if [[ $EUID -ne 0 ]]; then
   echo "Este script debe ejecutarse como root (sudo)." 
   exit 1
fi

# Preparación inicial del entorno
prepare_environment

while true; do
    clear
    echo "=========================================================="
    echo "    SISTEMA DE PROVISIÓN HTTP - UBUNTU SERVER"
    echo "=========================================================="
    echo "1) Instalar Apache2"
    echo "2) Instalar Nginx"
    echo "3) Instalar Apache Tomcat"
    echo "4) Salir"
    echo "----------------------------------------------------------"
    read -p "Seleccione una opción: " OPT

    case $OPT in
        1) deploy_service "apache2" ;;
        2) deploy_service "nginx" ;;
        3) deploy_tomcat ;;
        4) echo "Saliendo..."; exit 0 ;;
        *) echo "Opción no válida."; sleep 2 ;;
    esac
done