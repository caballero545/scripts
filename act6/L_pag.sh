#!/bin/bash
# ==============================================================
# MAIN SCRIPT: provisioner_linux.sh
# Provisionador HTTP Automatizado - Ubuntu Server
# Uso: sudo bash provisioner_linux.sh
# ==============================================================

FUNCTIONS_FILE="$(dirname "$0")/Lhttp.sh"

# ── Cargar funciones ────────────────────────────────────────
if [[ -f "$FUNCTIONS_FILE" ]]; then
    # shellcheck source=./Lhttp.sh
    source "$FUNCTIONS_FILE"
else
    echo "[ERROR] No se encontró el archivo de funciones: $FUNCTIONS_FILE"
    echo "        Asegúrate de que Lhttp.sh esté en el mismo directorio."
    exit 1
fi

# ── Verificar privilegios root ──────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Debes ejecutar este script como root (sudo)."
    exit 1
fi

# ── Preparar entorno (limpiar puertos, reparar APT) ─────────
prepare_environment

# ── Menú principal ──────────────────────────────────────────
while true; do
    clear
    echo ""
    echo "  ╔═══════════════════════════════════════════════════════╗"
    echo "  ║        PROVISIONADOR HTTP AUTOMATIZADO - SSH          ║"
    echo "  ║              Ubuntu Server | Bash v$(bash --version | head -1 | awk '{print $4}')              ║"
    echo "  ╠═══════════════════════════════════════════════════════╣"
    echo "  ║                                                       ║"
    echo "  ║   1)  Desplegar Apache2   (versión dinámica via APT)  ║"
    echo "  ║   2)  Desplegar Nginx     (versión dinámica via APT)  ║"
    echo "  ║   3)  Desplegar Tomcat    (descarga desde Apache.org) ║"
    echo "  ║   4)  Salir                                           ║"
    echo "  ║                                                       ║"
    echo "  ╚═══════════════════════════════════════════════════════╝"
    echo ""

    read -rp "  Seleccione una opción [1-4]: " OPT

    # Validar: solo dígitos, sin espacios ni caracteres raros
    OPT="${OPT//[^0-9]/}"

    case "$OPT" in
        1) deploy_service "apache2" ;;
        2) deploy_service "nginx"   ;;
        3) deploy_tomcat            ;;
        4)
            echo ""
            echo "  Cerrando sesión de aprovisionamiento."
            echo ""
            exit 0
            ;;
        *)
            echo "  Opción inválida. Intenta de nuevo."
            sleep 1
            ;;
    esac

    echo ""
    read -rp "  Presiona Enter para volver al menú..." _PAUSE
done