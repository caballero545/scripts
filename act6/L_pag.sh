#!/bin/bash
# ==============================================================
# MAIN SCRIPT: provisioner_linux.sh
# Provisionador HTTP Automatizado - Ubuntu Server
# Uso: sudo bash provisioner_linux.sh
# ==============================================================

FUNCTIONS_FILE="$(dirname "$0")/Lhttp.sh"

if [[ ! -f "$FUNCTIONS_FILE" ]]; then
    echo "[ERROR] No se encontro: $FUNCTIONS_FILE"
    echo "        Pon Lhttp.sh en el mismo directorio que este script."
    exit 1
fi

source "$FUNCTIONS_FILE"

if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Ejecuta como root: sudo bash provisioner_linux.sh"
    exit 1
fi

# Preparar entorno (limpia APT, UFW, puertos web)
prepare_environment

while true; do
    clear
    echo ""
    echo "  PROVISIONADOR HTTP AUTOMATIZADO - SSH"
    echo "  Ubuntu Server | Bash $(bash --version | head -1 | awk '{print $4}')"
    echo ""
    echo "  1) Desplegar Apache2   (versiones dinamicas via APT)"
    echo "  2) Desplegar Nginx     (versiones dinamicas via APT)"
    echo "  3) Desplegar Tomcat    (descarga desde archive.apache.org)"
    echo "  4) Salir"
    echo ""

    read -rp "  Opcion [1-4]: " OPT
    OPT="${OPT//[^0-9]/}"

    case "$OPT" in
        1) deploy_service "apache2" ;;
        2) deploy_service "nginx"   ;;
        3) deploy_tomcat            ;;
        4) echo ""; echo "  Hasta luego."; echo ""; exit 0 ;;
        *) echo "  Opcion invalida."; sleep 1 ;;
    esac

    echo ""
    read -rp "  Presiona Enter para continuar..." _
done