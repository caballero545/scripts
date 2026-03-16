#!/bin/bash
# ==========================================================
# MAIN SCRIPT: provisioner_linux.sh
# ==========================================================

FUNCTIONS_FILE="./Lhttp.sh"

if [[ -f "$FUNCTIONS_FILE" ]]; then
    source "$FUNCTIONS_FILE"
else
    echo "Error crítico: No se encontró el archivo de funciones $FUNCTIONS_FILE"
    exit 1
fi

if [[ $EUID -ne 0 ]]; then
   echo "CRÍTICO: Debes ejecutar este script con sudo." 
   exit 1
fi

# 1. Preparar el sistema
prepare_environment

# 2. Menú Interactivo
while true; do
    clear
    echo "=========================================================="
    echo "      PROVISIONADOR HTTP AUTOMATIZADO (SSH MODE)"
    echo "=========================================================="
    echo "1) Desplegar Apache2 (Dinamico)"
    echo "2) Desplegar Nginx (Dinamico)"
    echo "3) Desplegar Apache Tomcat (Manual/Seguro)"
    echo "4) Salir"
    echo "----------------------------------------------------------"
    read -p "Seleccione una opción [1-4]: " OPT

    case $OPT in
        1) deploy_service "apache2" ;;
        2) deploy_service "nginx" ;;
        3) deploy_tomcat ;;
        4) echo "Cerrando sesión de aprovisionamiento."; exit 0 ;;
        *) echo "Opción inválida. Intente de nuevo."; sleep 1 ;;
    esac
done