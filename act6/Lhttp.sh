#!/bin/bash
# ==============================================================
# ARCHIVO DE FUNCIONES: Lhttp.sh
# Provisionador HTTP - Linux (Ubuntu Server)
# Requiere: provisioner_linux.sh como main script
# ==============================================================

LOG="/tmp/http_provision.log"

# ──────────────────────────────────────────────
# LOG / DISPLAY
# ──────────────────────────────────────────────
log() {
    echo -e "$1"
    echo "$(date '+%F %T') | $1" >> "$LOG"
}

log_ok()  { log "\e[32m[OK]\e[0m  $1"; }
log_err() { log "\e[31m[ERR]\e[0m $1"; }
log_inf() { log "\e[36m[~]\e[0m   $1"; }
log_war() { log "\e[33m[!]\e[0m   $1"; }

# ──────────────────────────────────────────────
# ESPERAR APT (con timeout de seguridad)
# ──────────────────────────────────────────────
wait_for_apt() {
    local INTENTOS=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
       || fuser /var/lib/dpkg/lock          >/dev/null 2>&1; do
        log_inf "APT ocupado, esperando... ($INTENTOS)"
        sleep 3
        ((INTENTOS++))
        if ((INTENTOS > 15)); then
            log_war "APT bloqueado demasiado tiempo. Forzando liberación..."
            rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock
            dpkg --configure -a >/dev/null 2>&1 || true
            break
        fi
    done
}

# ──────────────────────────────────────────────
# REPARAR SISTEMA
# ──────────────────────────────────────────────
fix_system() {
    log_inf "Verificando integridad del sistema APT..."
    rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock
    dpkg --configure -a >/dev/null 2>&1 || true
    apt-get install -f -y -qq >/dev/null 2>&1 || true
    apt-get clean -qq
    apt-get update -qq -y >/dev/null 2>&1
    log_ok "Sistema APT listo"
}

# ──────────────────────────────────────────────
# LIMPIAR PUERTOS WEB EN FIREWALL (al iniciar)
# ──────────────────────────────────────────────
clean_firewall_ports() {
    log_inf "Limpiando reglas firewall de puertos web anteriores..."
    local PUERTOS_WEB=(80 8080 8888 8000 8443 3000 4000 8008 9090)
    for P in "${PUERTOS_WEB[@]}"; do
        ufw delete allow "${P}/tcp" >/dev/null 2>&1
        ufw delete allow "${P}"     >/dev/null 2>&1
    done
    log_ok "Firewall web limpio. Solo SSH (22) activo."
}

# ──────────────────────────────────────────────
# PREPARAR ENTORNO
# ──────────────────────────────────────────────
prepare_environment() {
    log "═══════════════════════════════════════════"
    log "  Preparando entorno de aprovisionamiento"
    log "═══════════════════════════════════════════"

    wait_for_apt
    fix_system

    log_inf "Instalando dependencias base..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        lsof curl ufw gawk sed iproute2 net-tools wget tar \
        >/dev/null 2>&1

    # Asegurar UFW con solo SSH habilitado
    ufw allow 22/tcp >/dev/null 2>&1
    echo "y" | ufw enable >/dev/null 2>&1
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1

    # Limpiar puertos web previos para empezar limpio
    clean_firewall_ports

    log_ok "Entorno listo"
    echo ""
}

# ──────────────────────────────────────────────
# VALIDAR PUERTO
# ──────────────────────────────────────────────
validate_port() {
    local P="$1"

    # Solo numérico
    if [[ ! "$P" =~ ^[0-9]+$ ]]; then
        log_war "El puerto debe ser un número entero."
        return 1
    fi

    # Rango válido
    if ((P < 1 || P > 65535)); then
        log_war "Puerto fuera de rango válido (1-65535)."
        return 1
    fi

    # Puertos reservados para otros servicios
    case "$P" in
        21)    log_war "Puerto $P reservado para FTP.";        return 1 ;;
        22)    log_war "Puerto $P reservado para SSH.";        return 1 ;;
        25)    log_war "Puerto $P reservado para SMTP.";       return 1 ;;
        53)    log_war "Puerto $P reservado para DNS.";        return 1 ;;
        443)   log_war "Puerto $P reservado para HTTPS.";      return 1 ;;
        3306)  log_war "Puerto $P reservado para MySQL.";      return 1 ;;
        3389)  log_war "Puerto $P reservado para RDP.";        return 1 ;;
        5432)  log_war "Puerto $P reservado para PostgreSQL."; return 1 ;;
    esac

    # Verificar si el puerto ya está en uso (usando ss)
    if ss -tlnp 2>/dev/null | grep -q ":${P} "; then
        log_war "Puerto $P ya está en uso por otro proceso."
        return 1
    fi

    return 0
}

# ──────────────────────────────────────────────
# PEDIR PUERTO CON VALIDACIÓN
# ──────────────────────────────────────────────
ask_port() {
    # $1 = nombre de variable donde guardar el resultado (nameref)
    local -n _PORT_OUT=$1
    local PROMPT="${2:-Puerto de escucha}"

    while true; do
        read -rp "  $PROMPT (ej: 80, 8080, 8888): " _PORT_OUT

        # Validar no vacío ni con caracteres raros
        if [[ -z "$_PORT_OUT" || "$_PORT_OUT" =~ [^0-9] ]]; then
            log_war "Entrada inválida. Ingresa solo números."
            continue
        fi

        if validate_port "$_PORT_OUT"; then
            log_ok "Puerto $_PORT_OUT válido y disponible."
            break
        fi
    done
}

# ──────────────────────────────────────────────
# OBTENER VERSIONES DINÁMICAS (APT)
# ──────────────────────────────────────────────
get_versions() {
    local PKG="$1"
    apt-cache madison "$PKG" 2>/dev/null | awk '{print $3}' | sort -Vru
}

# ──────────────────────────────────────────────
# MENÚ DE SELECCIÓN DE VERSIÓN
# ──────────────────────────────────────────────
select_version() {
    # $1 = paquete, $2 = nombre de variable resultado (nameref)
    local PKG="$1"
    local -n _VER_OUT=$2

    log_inf "Consultando versiones disponibles para $PKG en repositorios..."
    mapfile -t VERS < <(get_versions "$PKG")

    if [[ ${#VERS[@]} -eq 0 ]]; then
        log_war "No se encontraron versiones específicas. Se instalará la última disponible."
        _VER_OUT="latest"
        return
    fi

    echo ""
    echo "  ┌─────────────────────────────────────────────────┐"
    printf  "  │   Versiones disponibles para %-18s│\n" "$PKG"
    echo "  ├─────────────────────────────────────────────────┤"

    for i in "${!VERS[@]}"; do
        local LABEL=""
        if [[ $i -eq 0 ]]; then
            LABEL=" <-- Más reciente"
        elif [[ $i -eq $((${#VERS[@]}-1)) ]]; then
            LABEL=" <-- LTS/Estable"
        fi
        printf "  │  %2d) %-43s│\n" "$((i+1))" "${VERS[$i]}${LABEL}"
    done

    echo "  └─────────────────────────────────────────────────┘"
    echo ""

    local SEL
    while true; do
        read -rp "  Seleccione número de versión: " SEL
        # Validar: solo dígitos, en rango
        if [[ "$SEL" =~ ^[0-9]+$ ]] && ((SEL >= 1 && SEL <= ${#VERS[@]})); then
            break
        fi
        log_war "Opción inválida. Ingresa un número entre 1 y ${#VERS[@]}."
    done

    _VER_OUT="${VERS[$((SEL-1))]}"
    log_ok "Versión seleccionada: $_VER_OUT"
}

# ──────────────────────────────────────────────
# INDEX.HTML PERSONALIZADO
# ──────────────────────────────────────────────
create_index() {
    local NAME="$1" VERSION="$2" PORT="$3" ROOT="$4"

    mkdir -p "$ROOT"

    cat > "$ROOT/index.html" <<HTML
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$NAME - Activo</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: 'Courier New', monospace;
      background: #0d1117;
      color: #c9d1d9;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
    }
    .card {
      border: 1px solid #30363d;
      border-radius: 8px;
      padding: 40px 60px;
      text-align: center;
      background: #161b22;
      box-shadow: 0 0 30px rgba(0,210,255,0.08);
    }
    .status { color: #3fb950; font-size: 0.9em; margin-bottom: 8px; }
    h1 { color: #58a6ff; font-size: 2em; margin-bottom: 24px; }
    .badge {
      display: inline-block;
      background: #21262d;
      border: 1px solid #30363d;
      border-radius: 4px;
      padding: 8px 20px;
      margin: 6px;
      font-size: 0.95em;
    }
    .badge span { color: #58a6ff; font-weight: bold; }
    .footer { margin-top: 24px; font-size: 0.75em; color: #484f58; }
  </style>
</head>
<body>
  <div class="card">
    <div class="status">● SERVIDOR ACTIVO</div>
    <h1>$NAME</h1>
    <div class="badge">Servicio: <span>$NAME</span></div>
    <div class="badge">Versión: <span>$VERSION</span></div>
    <div class="badge">Puerto: <span>$PORT</span></div>
    <div class="footer">Aprovisionado automáticamente vía SSH</div>
  </div>
</body>
</html>
HTML

    log_ok "index.html creado en $ROOT"
}

# ──────────────────────────────────────────────
# HARDENING APACHE
# ──────────────────────────────────────────────
harden_apache() {
    log_inf "Aplicando hardening a Apache2..."

    local SEC="/etc/apache2/conf-enabled/security.conf"

    # ServerTokens y ServerSignature
    if [[ -f "$SEC" ]]; then
        sed -i "s/^ServerTokens .*/ServerTokens Prod/"    "$SEC"
        sed -i "s/^#ServerTokens .*/ServerTokens Prod/"   "$SEC"
        sed -i "s/^ServerSignature .*/ServerSignature Off/" "$SEC"
        sed -i "s/^#ServerSignature .*/ServerSignature Off/" "$SEC"
    else
        # Si no existe, añadir a apache2.conf
        grep -q "ServerTokens Prod" /etc/apache2/apache2.conf || \
            echo -e "\nServerTokens Prod\nServerSignature Off" >> /etc/apache2/apache2.conf
    fi

    # Activar mod_headers
    a2enmod headers >/dev/null 2>&1

    # Configuración de seguridad adicional
    cat > /etc/apache2/conf-available/seguridad.conf <<'APACHECONF'
<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header unset Server
    Header always unset X-Powered-By
</IfModule>

# Deshabilitar métodos peligrosos
TraceEnable Off

<LimitExcept GET POST HEAD>
    Require all denied
</LimitExcept>
APACHECONF

    a2enconf seguridad >/dev/null 2>&1

    log_ok "Hardening Apache aplicado"
}

# ──────────────────────────────────────────────
# HARDENING NGINX
# ──────────────────────────────────────────────
harden_nginx() {
    log_inf "Aplicando hardening a Nginx..."

    local NGINX_CONF="/etc/nginx/nginx.conf"

    # server_tokens off
    if grep -q "server_tokens" "$NGINX_CONF"; then
        sed -i "s/.*server_tokens.*/\tserver_tokens off;/" "$NGINX_CONF"
    else
        sed -i "/http {/a\\\\tserver_tokens off;" "$NGINX_CONF"
    fi

    # Crear snippet de seguridad para incluir en el server block
    cat > /etc/nginx/snippets/seguridad.conf <<'NGINXSEC'
# Security headers
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;

# Bloquear métodos peligrosos
if ($request_method !~ ^(GET|POST|HEAD)$ ) {
    return 405;
}
NGINXSEC

    log_ok "Hardening Nginx aplicado"
}

# ──────────────────────────────────────────────
# VERIFICAR SI HAY INSTALACIÓN EXISTENTE
# ──────────────────────────────────────────────
check_existing() {
    local SERVICE="$1"

    case "$SERVICE" in
        apache2)
            if dpkg -l apache2 2>/dev/null | grep -q "^ii"; then
                dpkg -l apache2 2>/dev/null | awk '/^ii/{print $3}'
                return 0
            fi
            ;;
        nginx)
            if dpkg -l nginx 2>/dev/null | grep -q "^ii"; then
                dpkg -l nginx 2>/dev/null | awk '/^ii/{print $3}'
                return 0
            fi
            ;;
        tomcat)
            if [[ -d /opt/tomcat ]] || systemctl list-units --full -all 2>/dev/null | grep -q "tomcat"; then
                # Intentar obtener versión del RELEASE-NOTES
                local V
                V=$(grep -m1 "Apache Tomcat Version" /opt/tomcat/RELEASE-NOTES 2>/dev/null | awk '{print $NF}')
                echo "${V:-instalado}"
                return 0
            fi
            ;;
    esac

    return 1
}

# ──────────────────────────────────────────────
# PURGAR SERVICIO COMPLETAMENTE
# ──────────────────────────────────────────────
purge_service() {
    local SERVICE="$1"

    log_war "Eliminando instalación anterior de $SERVICE (purge completo)..."

    case "$SERVICE" in
        apache2)
            systemctl stop apache2    >/dev/null 2>&1
            systemctl disable apache2 >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq \
                apache2 apache2-utils apache2-bin apache2-data \
                libapache2-mod-* >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -qq >/dev/null 2>&1 || true
            rm -rf /etc/apache2 /var/www/html/* /var/log/apache2 /var/run/apache2
            log_ok "Apache2 purgado completamente"
            ;;

        nginx)
            systemctl stop nginx    >/dev/null 2>&1
            systemctl disable nginx >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get purge -y -qq \
                nginx nginx-common nginx-full nginx-core nginx-extras >/dev/null 2>&1 || true
            DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -qq >/dev/null 2>&1 || true
            rm -rf /etc/nginx /var/www/html/* /var/log/nginx /var/run/nginx
            log_ok "Nginx purgado completamente"
            ;;

        tomcat)
            # Detener proceso Tomcat
            systemctl stop tomcat    >/dev/null 2>&1
            systemctl disable tomcat >/dev/null 2>&1
            pkill -f "catalina"  >/dev/null 2>&1 || true
            pkill -u tomcat      >/dev/null 2>&1 || true
            sleep 2

            rm -rf /opt/tomcat
            rm -f  /etc/systemd/system/tomcat.service
            userdel -r tomcat >/dev/null 2>&1 || true
            groupdel  tomcat  >/dev/null 2>&1 || true

            systemctl daemon-reload >/dev/null 2>&1
            log_ok "Tomcat purgado completamente"
            ;;
    esac
}

# ──────────────────────────────────────────────
# VERIFICAR SERVICIO ACTIVO (con reintentos)
# ──────────────────────────────────────────────
check_service() {
    local SVC="$1"
    local INTENTOS=0

    while ((INTENTOS < 6)); do
        if systemctl is-active --quiet "$SVC" 2>/dev/null; then
            log_ok "$SVC está corriendo."
            return 0
        fi
        log_inf "Esperando a que $SVC inicie... ($((INTENTOS+1))/6)"
        sleep 2
        ((INTENTOS++))
    done

    log_err "$SVC no inició correctamente. Últimas líneas del log:"
    journalctl -u "$SVC" --no-pager -n 15 2>/dev/null || true
    return 1
}

# ──────────────────────────────────────────────
# CONFIGURAR APACHE2
# ──────────────────────────────────────────────
_configure_apache() {
    local PORT="$1"
    local VERSION="$2"

    log_inf "Configurando Apache2 en puerto $PORT..."

    systemctl stop apache2 >/dev/null 2>&1

    # ── ports.conf ──────────────────────────────
    # Reemplazar CUALQUIER línea Listen existente
    sed -i "s/^Listen .*/Listen $PORT/" /etc/apache2/ports.conf

    # Si no existe la línea Listen, agregarla
    grep -q "^Listen" /etc/apache2/ports.conf || echo "Listen $PORT" >> /etc/apache2/ports.conf

    # ── VirtualHost ─────────────────────────────
    if [[ -f /etc/apache2/sites-available/000-default.conf ]]; then
        sed -i "s/<VirtualHost \*:[0-9]*>/<VirtualHost *:$PORT>/" \
            /etc/apache2/sites-available/000-default.conf
    fi

    # ── Crear directorio y permisos ─────────────
    mkdir -p /var/www/html
    chown -R www-data:www-data /var/www/html
    chmod -R 750 /var/www/html

    # ── Index personalizado ─────────────────────
    create_index "Apache2" "$VERSION" "$PORT" "/var/www/html"

    # ── Hardening ───────────────────────────────
    harden_apache

    # ── Iniciar ─────────────────────────────────
    systemctl enable apache2 >/dev/null 2>&1
    systemctl start apache2

    # Test de configuración
    apache2ctl configtest 2>&1 | grep -v "^$" | head -5

    log_ok "Apache2 configurado"
}

# ──────────────────────────────────────────────
# CONFIGURAR NGINX
# ──────────────────────────────────────────────
_configure_nginx() {
    local PORT="$1"
    local VERSION="$2"

    log_inf "Configurando Nginx en puerto $PORT..."

    systemctl stop nginx >/dev/null 2>&1

    # ── Reescribir el default site (más seguro que sed) ──
    cat > /etc/nginx/sites-available/default <<NGINXCONF
server {
    listen ${PORT} default_server;
    listen [::]:${PORT} default_server;

    root /var/www/html;
    index index.html index.htm;

    server_name _;

    # Incluir headers de seguridad
    include snippets/seguridad.conf;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # Bloquear acceso a archivos ocultos
    location ~ /\. {
        deny all;
    }
}
NGINXCONF

    # ── Crear snippets dir si no existe ─────────
    mkdir -p /etc/nginx/snippets

    # ── Directorio y permisos ───────────────────
    mkdir -p /var/www/html
    chown -R www-data:www-data /var/www/html
    chmod -R 750 /var/www/html

    # ── Index personalizado ─────────────────────
    create_index "Nginx" "$VERSION" "$PORT" "/var/www/html"

    # ── Hardening ───────────────────────────────
    harden_nginx

    # ── Verificar configuración antes de iniciar ─
    if ! nginx -t >/dev/null 2>&1; then
        log_err "Error en configuración de Nginx:"
        nginx -t
        return 1
    fi

    systemctl enable nginx >/dev/null 2>&1
    systemctl start nginx

    log_ok "Nginx configurado"
}

# ──────────────────────────────────────────────
# DEPLOY APACHE2 / NGINX (función principal)
# ──────────────────────────────────────────────
deploy_service() {
    local SERVICE="$1"
    local SVC_DISPLAY="${SERVICE^}"  # Capitalizar primera letra

    echo ""
    log "╔══════════════════════════════════════════════╗"
    log "║   DESPLIEGUE DE $SVC_DISPLAY"
    log "╚══════════════════════════════════════════════╝"

    # ── 1. Verificar si ya hay instalación previa ─
    local VERSION_EXISTENTE
    VERSION_EXISTENTE=$(check_existing "$SERVICE")

    if [[ -n "$VERSION_EXISTENTE" ]]; then
        echo ""
        log_war "Se encontró $SVC_DISPLAY ya instalado (versión: $VERSION_EXISTENTE)"
        echo ""

        local CONFIRM
        while true; do
            read -rp "  ¿Desea reinstalar? Se eliminará todo rastro anterior [s/N]: " CONFIRM
            # Sanitizar entrada
            CONFIRM="${CONFIRM,,}"
            CONFIRM="${CONFIRM//[^a-z]/}"
            case "$CONFIRM" in
                s|si|yes|y) break ;;
                n|no|"")
                    log_inf "Instalación cancelada. Volviendo al menú."
                    sleep 1
                    return 0
                    ;;
                *) log_war "Responde s (sí) o n (no)." ;;
            esac
        done

        # Purgar instalación anterior
        purge_service "$SERVICE"
        wait_for_apt
        fix_system
    fi

    # ── 2. Seleccionar versión ──────────────────
    local VERSION
    select_version "$SERVICE" VERSION

    # ── 3. Seleccionar puerto ───────────────────
    local PORT
    ask_port PORT "  Puerto de escucha para $SVC_DISPLAY"

    # ── 4. Instalar ─────────────────────────────
    echo ""
    log_inf "Instalando $SERVICE..."

    wait_for_apt

    if [[ "$VERSION" == "latest" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$SERVICE" >/dev/null 2>&1
    else
        # Intentar versión exacta, si falla instalar la disponible
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${SERVICE}=${VERSION}" >/dev/null 2>&1 || {
            log_war "No se pudo instalar la versión exacta. Instalando la última disponible..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$SERVICE" >/dev/null 2>&1
        }
    fi

    # Verificar que se instaló
    if ! dpkg -l "$SERVICE" 2>/dev/null | grep -q "^ii"; then
        log_err "Fallo crítico: $SERVICE no se instaló correctamente."
        return 1
    fi

    # Obtener versión real instalada
    VERSION=$(dpkg -l "$SERVICE" 2>/dev/null | awk '/^ii/{print $3}' | head -1)
    log_ok "$SERVICE instalado: $VERSION"

    # ── 5. Configurar y aplicar puerto ──────────
    if [[ "$SERVICE" == "apache2" ]]; then
        _configure_apache "$PORT" "$VERSION" || return 1
    elif [[ "$SERVICE" == "nginx" ]]; then
        _configure_nginx  "$PORT" "$VERSION" || return 1
    fi

    # ── 6. Abrir puerto en firewall ─────────────
    ufw allow "${PORT}/tcp" >/dev/null 2>&1
    log_ok "Puerto $PORT abierto en UFW"

    # ── 7. Verificar servicio ───────────────────
    if check_service "$SERVICE"; then
        local IP
        IP=$(hostname -I 2>/dev/null | awk '{print $1}')
        echo ""
        log "╔══════════════════════════════════════════════════════╗"
        log "║  ✓ $SVC_DISPLAY desplegado exitosamente"
        log "║  URL: http://${IP}:${PORT}"
        log "║  Verificar: curl -I http://${IP}:${PORT}"
        log "╚══════════════════════════════════════════════════════╝"
    else
        log_err "$SERVICE no inició. Revisa $LOG para detalles."
        return 1
    fi
}

# ──────────────────────────────────────────────
# DEPLOY TOMCAT
# ──────────────────────────────────────────────
deploy_tomcat() {
    echo ""
    log "╔══════════════════════════════════════════════╗"
    log "║   DESPLIEGUE DE APACHE TOMCAT"
    log "╚══════════════════════════════════════════════╝"

    # ── 1. Verificar instalación previa ─────────
    local VERSION_EXISTENTE
    VERSION_EXISTENTE=$(check_existing "tomcat")

    if [[ -n "$VERSION_EXISTENTE" ]]; then
        echo ""
        log_war "Se encontró Tomcat ya instalado (versión: $VERSION_EXISTENTE)"
        echo ""

        local CONFIRM
        while true; do
            read -rp "  ¿Desea reinstalar? Se eliminará /opt/tomcat y el servicio [s/N]: " CONFIRM
            CONFIRM="${CONFIRM,,}"
            CONFIRM="${CONFIRM//[^a-z]/}"
            case "$CONFIRM" in
                s|si|yes|y) break ;;
                n|no|"")
                    log_inf "Instalación cancelada. Volviendo al menú."
                    sleep 1
                    return 0
                    ;;
                *) log_war "Responde s (sí) o n (no)." ;;
            esac
        done

        purge_service "tomcat"
    fi

    # ── 2. Seleccionar versión ──────────────────
    echo ""
    echo "  ┌──────────────────────────────────────────────────┐"
    echo "  │         Versiones disponibles de Tomcat          │"
    echo "  ├──────────────────────────────────────────────────┤"
    echo "  │  1) 10.1.18  <-- Más reciente (Java 11+)         │"
    echo "  │  2) 10.1.16  <-- Estable (Java 11+)              │"
    echo "  │  3)  9.0.84  <-- LTS anterior (Java 8+)          │"
    echo "  └──────────────────────────────────────────────────┘"
    echo ""

    local VER_SEL MAJOR
    while true; do
        read -rp "  Seleccione versión [1-3]: " VER_SEL
        if [[ "$VER_SEL" =~ ^[1-3]$ ]]; then break; fi
        log_war "Opción inválida."
    done

    local VER
    case "$VER_SEL" in
        1) VER="10.1.18"; MAJOR="10" ;;
        2) VER="10.1.16"; MAJOR="10" ;;
        3) VER="9.0.84";  MAJOR="9"  ;;
    esac

    # ── 3. Seleccionar puerto ───────────────────
    local PORT
    ask_port PORT "  Puerto de escucha para Tomcat"

    # ── 4. Instalar Java ─────────────────────────
    log_inf "Instalando Java (requerido por Tomcat)..."
    wait_for_apt

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        default-jdk wget tar >/dev/null 2>&1

    if ! command -v java &>/dev/null; then
        log_err "Java no se instaló. Abortando."
        return 1
    fi

    local JAVA_VER
    JAVA_VER=$(java -version 2>&1 | head -1)
    log_ok "Java disponible: $JAVA_VER"

    # ── 5. Crear usuario dedicado ────────────────
    if ! id tomcat &>/dev/null; then
        useradd -m -U -d /opt/tomcat -s /bin/false tomcat
        log_ok "Usuario 'tomcat' creado"
    fi

    # ── 6. Descargar Tomcat ──────────────────────
    local FILE="/tmp/tomcat-${VER}.tar.gz"
    local URL="https://archive.apache.org/dist/tomcat/tomcat-${MAJOR}/v${VER}/bin/apache-tomcat-${VER}.tar.gz"

    log_inf "Descargando Tomcat $VER..."
    log_inf "URL: $URL"

    # Usar wget con timeout y reintentos
    wget -q --timeout=60 --tries=3 --show-progress \
         -O "$FILE" "$URL" 2>/dev/null || \
    wget --timeout=60 --tries=3 -O "$FILE" "$URL"

    if [[ ! -s "$FILE" ]]; then
        log_err "Descarga fallida. Verifica la conectividad a internet."
        rm -f "$FILE"
        return 1
    fi

    log_ok "Descarga completa: $(du -sh "$FILE" | cut -f1)"

    # ── 7. Extraer e instalar ────────────────────
    log_inf "Extrayendo Tomcat en /opt/tomcat..."
    rm -rf /opt/tomcat
    mkdir -p /opt/tomcat

    tar -xzf "$FILE" -C /opt/tomcat --strip-components=1 || {
        log_err "Error extrayendo el archivo tar.gz"
        rm -f "$FILE"
        return 1
    }

    rm -f "$FILE"

    # ── 8. Permisos ──────────────────────────────
    chown -R tomcat:tomcat /opt/tomcat
    chmod -R 750 /opt/tomcat
    # webapps necesita ser accesible para servir contenido
    chmod -R 755 /opt/tomcat/webapps

    log_ok "Permisos aplicados"

    # ── 9. Configurar puerto en server.xml ───────
    # Reemplazar el conector HTTP/1.1
    sed -i "s/port=\"[0-9]*\" protocol=\"HTTP\/1.1\"/port=\"${PORT}\" protocol=\"HTTP\/1.1\"/" \
        /opt/tomcat/conf/server.xml

    log_ok "Puerto $PORT configurado en server.xml"

    # ── 10. Index personalizado ──────────────────
    create_index "Tomcat" "$VER" "$PORT" "/opt/tomcat/webapps/ROOT"
    chown -R tomcat:tomcat /opt/tomcat/webapps/ROOT

    # ── 11. Encontrar JAVA_HOME ──────────────────
    local JAVA_HOME_DIR
    JAVA_HOME_DIR=$(dirname "$(dirname "$(readlink -f "$(which java)")")")
    log_inf "JAVA_HOME detectado: $JAVA_HOME_DIR"

    # ── 12. Crear servicio systemd ───────────────
    cat > /etc/systemd/system/tomcat.service <<SYSTEMD
[Unit]
Description=Apache Tomcat ${VER} Web Server
Documentation=https://tomcat.apache.org
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat

Environment="JAVA_HOME=${JAVA_HOME_DIR}"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_BASE=/opt/tomcat"
Environment="CATALINA_PID=/opt/tomcat/temp/tomcat.pid"
Environment="CATALINA_OPTS=-Xms256M -Xmx512M -server -XX:+UseParallelGC"

ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh

Restart=on-failure
RestartSec=5
PrivateTmp=true

[Install]
WantedBy=multi-user.target
SYSTEMD

    systemctl daemon-reload
    systemctl enable tomcat >/dev/null 2>&1
    systemctl start tomcat

    # ── 13. Abrir firewall ───────────────────────
    ufw allow "${PORT}/tcp" >/dev/null 2>&1
    log_ok "Puerto $PORT abierto en UFW"

    # ── 14. Esperar arranque y verificar ─────────
    log_inf "Esperando que Tomcat arranque (puede tardar ~10s)..."
    sleep 8

    if check_service "tomcat"; then
        local IP
        IP=$(hostname -I 2>/dev/null | awk '{print $1}')
        echo ""
        log "╔══════════════════════════════════════════════════════╗"
        log "║  ✓ Tomcat ${VER} desplegado exitosamente"
        log "║  URL: http://${IP}:${PORT}"
        log "║  Verificar: curl -I http://${IP}:${PORT}"
        log "╚══════════════════════════════════════════════════════╝"
    else
        log_err "Tomcat no inició. Revisa: journalctl -u tomcat -n 30"
        return 1
    fi
}