#!/bin/bash
# ==============================================================
# ARCHIVO DE FUNCIONES: Lhttp.sh
# Provisionador HTTP - Linux (Ubuntu Server)
# ==============================================================

LOG="/tmp/http_provision.log"

log()     { echo -e "$1" | tee -a "$LOG"; }
log_ok()  { echo -e "  [OK]  $1" | tee -a "$LOG"; }
log_err() { echo -e "  [ERR] $1" | tee -a "$LOG"; }
log_inf() { echo -e "  [~]   $1" | tee -a "$LOG"; }
log_war() { echo -e "  [!]   $1" | tee -a "$LOG"; }

# --------------------------------------------------------------
# ESPERAR APT
# --------------------------------------------------------------
wait_for_apt() {
    local i=0
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
       || fuser /var/lib/dpkg/lock          >/dev/null 2>&1; do
        log_inf "APT ocupado, esperando... ($i)"
        sleep 3
        ((i++))
        if ((i > 20)); then
            log_war "Forzando liberacion de APT..."
            rm -f /var/lib/dpkg/lock-frontend \
                  /var/lib/dpkg/lock \
                  /var/cache/apt/archives/lock
            dpkg --configure -a >/dev/null 2>&1 || true
            break
        fi
    done
}

# --------------------------------------------------------------
# REPARAR APT
# --------------------------------------------------------------
fix_apt() {
    log_inf "Reparando APT..."
    rm -f /var/lib/dpkg/lock-frontend \
          /var/lib/dpkg/lock \
          /var/cache/apt/archives/lock
    dpkg --configure -a 2>&1 | tail -3
    apt-get install -f -y -q 2>&1 | tail -3
    apt-get clean -q
    apt-get update -q 2>&1 | tail -5
    log_ok "APT listo"
}

# --------------------------------------------------------------
# LIMPIAR PUERTOS WEB EN UFW
# --------------------------------------------------------------
clean_firewall_ports() {
    log_inf "Limpiando reglas UFW de puertos web anteriores..."

    local NUM
    # Repetir el proceso porque al borrar por numero los indices cambian
    local MAX_ITER=30
    local ITER=0

    while ((ITER < MAX_ITER)); do
        # Buscar la primera regla que no sea SSH (puerto 22)
        NUM=$(ufw status numbered 2>/dev/null \
              | grep -E "^\[[0-9]+\]" \
              | grep -vE "22/tcp|22 " \
              | grep -oP "^\[\K[0-9]+" \
              | head -1)

        if [[ -z "$NUM" ]]; then
            break  # No quedan reglas web
        fi

        echo "y" | ufw delete "$NUM" >/dev/null 2>&1
        ((ITER++))
    done

    log_ok "Firewall limpio (solo SSH activo)"
}

# --------------------------------------------------------------
# PREPARAR ENTORNO
# --------------------------------------------------------------
prepare_environment() {
    log "=== Preparando entorno ==="

    wait_for_apt
    fix_apt

    log_inf "Instalando dependencias base..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
        lsof curl ufw gawk sed iproute2 net-tools wget tar 2>&1 | tail -3

    # UFW: permitir solo SSH
    ufw allow 22/tcp >/dev/null 2>&1
    echo "y" | ufw enable >/dev/null 2>&1
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1

    # Limpiar puertos web previos
    clean_firewall_ports

    log_ok "Entorno listo"
    echo ""
}

# --------------------------------------------------------------
# VALIDAR PUERTO
# --------------------------------------------------------------
validate_port() {
    local P="$1"

    [[ ! "$P" =~ ^[0-9]+$ ]]  && log_war "Solo numeros."              && return 1
    ((P < 1 || P > 65535))     && log_war "Rango invalido (1-65535)." && return 1

    case "$P" in
        21)   log_war "Reservado: FTP.";        return 1 ;;
        22)   log_war "Reservado: SSH.";        return 1 ;;
        25)   log_war "Reservado: SMTP.";       return 1 ;;
        53)   log_war "Reservado: DNS.";        return 1 ;;
        443)  log_war "Reservado: HTTPS.";      return 1 ;;
        3306) log_war "Reservado: MySQL.";      return 1 ;;
        3389) log_war "Reservado: RDP.";        return 1 ;;
        5432) log_war "Reservado: PostgreSQL."; return 1 ;;
    esac

    if ss -tlnp 2>/dev/null | awk '{print $4}' | grep -qE ":${P}$"; then
        log_war "Puerto $P en uso por otro proceso."
        return 1
    fi

    return 0
}

# --------------------------------------------------------------
# PEDIR PUERTO
# --------------------------------------------------------------
ask_port() {
    local -n _PORT=$1
    local PROMPT="${2:-Puerto}"

    while true; do
        read -rp "  $PROMPT (ej: 80, 8080, 8888): " _PORT
        _PORT="${_PORT//[^0-9]/}"
        [[ -z "$_PORT" ]] && log_war "No puede estar vacio." && continue
        validate_port "$_PORT" && log_ok "Puerto $_PORT disponible." && break
    done
}

# --------------------------------------------------------------
# VERSIONES DESDE APT (dinamico)
# --------------------------------------------------------------
get_versions() {
    apt-cache madison "$1" 2>/dev/null | awk '{print $3}' | sort -Vru | head -10
}

# --------------------------------------------------------------
# SELECCIONAR VERSION
# --------------------------------------------------------------
select_version() {
    local PKG="$1"
    local -n _VER=$2

    log_inf "Consultando versiones de $PKG en APT..."
    mapfile -t VERS < <(get_versions "$PKG")

    if [[ ${#VERS[@]} -eq 0 ]]; then
        log_war "No se encontraron versiones. Se usara la ultima disponible."
        _VER="latest"
        return
    fi

    echo ""
    echo "  Versiones disponibles para $PKG:"
    for i in "${!VERS[@]}"; do
        local LABEL=""
        [[ $i -eq 0 ]]                  && LABEL="  <- Mas reciente"
        [[ $i -eq $((${#VERS[@]}-1)) ]] && LABEL="  <- LTS/Estable"
        printf "  %2d) %s%s\n" "$((i+1))" "${VERS[$i]}" "$LABEL"
    done
    echo ""

    local SEL
    while true; do
        read -rp "  Seleccione version [1-${#VERS[@]}]: " SEL
        SEL="${SEL//[^0-9]/}"
        [[ "$SEL" =~ ^[0-9]+$ ]] && ((SEL >= 1 && SEL <= ${#VERS[@]})) && break
        log_war "Opcion invalida. Ingresa un numero entre 1 y ${#VERS[@]}."
    done

    _VER="${VERS[$((SEL-1))]}"
    log_ok "Version seleccionada: $_VER"
}

# --------------------------------------------------------------
# INDEX.HTML
# --------------------------------------------------------------
create_index() {
    local NAME="$1" VER="$2" PORT="$3" ROOT="$4"
    mkdir -p "$ROOT"
    cat > "$ROOT/index.html" <<HTML
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>$NAME</title></head>
<body>
<h1>Servidor: $NAME</h1>
<p>Version: $VER</p>
<p>Puerto: $PORT</p>
<p>Aprovisionado via SSH</p>
</body>
</html>
HTML
    log_ok "index.html creado en $ROOT"
}

# --------------------------------------------------------------
# HARDENING APACHE
# --------------------------------------------------------------
harden_apache() {
    log_inf "Aplicando hardening Apache..."

    # security.conf puede estar en conf-available o conf-enabled
    local SEC
    for F in /etc/apache2/conf-enabled/security.conf \
             /etc/apache2/conf-available/security.conf \
             /etc/apache2/conf-available/security.conf; do
        [[ -f "$F" ]] && SEC="$F" && break
    done

    if [[ -n "$SEC" ]]; then
        sed -i "s/^ServerTokens.*/ServerTokens Prod/"     "$SEC"
        sed -i "s/^#ServerTokens.*/ServerTokens Prod/"    "$SEC"
        sed -i "s/^ServerSignature.*/ServerSignature Off/" "$SEC"
        sed -i "s/^#ServerSignature.*/ServerSignature Off/" "$SEC"
    fi

    a2enmod headers >/dev/null 2>&1

    cat > /etc/apache2/conf-available/seguridad.conf <<'EOF'
<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header unset Server
    Header always unset X-Powered-By
</IfModule>
TraceEnable Off
<LimitExcept GET POST HEAD>
    Require all denied
</LimitExcept>
EOF

    a2enconf seguridad >/dev/null 2>&1
    log_ok "Hardening Apache aplicado"
}

# --------------------------------------------------------------
# HARDENING NGINX
# --------------------------------------------------------------
harden_nginx() {
    log_inf "Aplicando hardening Nginx..."

    local NC="/etc/nginx/nginx.conf"
    if grep -q "server_tokens" "$NC"; then
        sed -i "s/.*server_tokens.*/\tserver_tokens off;/" "$NC"
    else
        sed -i "/http {/a\\\\tserver_tokens off;" "$NC"
    fi

    mkdir -p /etc/nginx/snippets
    cat > /etc/nginx/snippets/seguridad.conf <<'EOF'
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
if ($request_method !~ ^(GET|POST|HEAD)$ ) { return 405; }
EOF

    log_ok "Hardening Nginx aplicado"
}

# --------------------------------------------------------------
# VERIFICAR INSTALACION EXISTENTE
# Detecta: instalado completo (ii), parcial (iU/iF), o residual
# --------------------------------------------------------------
check_existing() {
    local SERVICE="$1"

    case "$SERVICE" in
        apache2|nginx)
            local LINE
            LINE=$(dpkg -l "$SERVICE" 2>/dev/null | grep -E "^[a-zA-Z]{2}\s+$SERVICE\s" | head -1)
            if [[ -n "$LINE" ]]; then
                local STATE VER
                STATE=$(echo "$LINE" | awk '{print $1}')
                VER=$(echo "$LINE" | awk '{print $3}')
                echo "$VER (dpkg: $STATE)"
                return 0
            fi
            # Archivos de configuracion residuales
            if [[ "$SERVICE" == "apache2" ]] && [[ -d /etc/apache2 ]]; then
                echo "config-residual (sin paquete dpkg)"
                return 0
            fi
            if [[ "$SERVICE" == "nginx" ]] && [[ -d /etc/nginx ]]; then
                echo "config-residual (sin paquete dpkg)"
                return 0
            fi
            ;;
        tomcat)
            if [[ -d /opt/tomcat ]] || systemctl list-unit-files 2>/dev/null | grep -q "^tomcat"; then
                local V
                V=$(grep -m1 "Apache Tomcat Version" /opt/tomcat/RELEASE-NOTES 2>/dev/null | awk '{print $NF}')
                echo "${V:-directorio-existente}"
                return 0
            fi
            ;;
    esac

    return 1
}

# --------------------------------------------------------------
# PURGAR SERVICIO
# --------------------------------------------------------------
purge_service() {
    local SERVICE="$1"
    log_war "Purgando $SERVICE por completo..."

    case "$SERVICE" in
        apache2)
            systemctl stop apache2    >/dev/null 2>&1
            systemctl disable apache2 >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get purge -y \
                apache2 apache2-utils apache2-bin apache2-data 2>&1 | tail -5
            DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -q 2>&1 | tail -3
            rm -rf /etc/apache2 /var/www/html /var/log/apache2 \
                   /var/run/apache2 /usr/lib/apache2 /usr/share/apache2
            log_ok "Apache2 purgado"
            ;;

        nginx)
            systemctl stop nginx    >/dev/null 2>&1
            systemctl disable nginx >/dev/null 2>&1
            DEBIAN_FRONTEND=noninteractive apt-get purge -y \
                nginx nginx-common nginx-full nginx-core nginx-extras 2>&1 | tail -5
            DEBIAN_FRONTEND=noninteractive apt-get autoremove -y -q 2>&1 | tail -3
            rm -rf /etc/nginx /var/www/html /var/log/nginx \
                   /var/run/nginx /usr/share/nginx
            log_ok "Nginx purgado"
            ;;

        tomcat)
            systemctl stop tomcat    >/dev/null 2>&1
            systemctl disable tomcat >/dev/null 2>&1
            pkill -f "catalina"      >/dev/null 2>&1 || true
            pkill -u tomcat          >/dev/null 2>&1 || true
            sleep 2
            rm -rf /opt/tomcat
            rm -f  /etc/systemd/system/tomcat.service
            userdel -r tomcat >/dev/null 2>&1 || true
            groupdel   tomcat >/dev/null 2>&1 || true
            systemctl daemon-reload >/dev/null 2>&1
            log_ok "Tomcat purgado"
            ;;
    esac

    wait_for_apt
    fix_apt
}

# --------------------------------------------------------------
# VERIFICAR SERVICIO ACTIVO
# --------------------------------------------------------------
check_service() {
    local SVC="$1"
    local i=0

    while ((i < 8)); do
        if systemctl is-active --quiet "$SVC" 2>/dev/null; then
            log_ok "$SVC esta corriendo."
            return 0
        fi
        log_inf "Esperando inicio de $SVC... ($((i+1))/8)"
        sleep 2
        ((i++))
    done

    log_err "$SVC no inicio. Log:"
    journalctl -u "$SVC" --no-pager -n 20 2>/dev/null
    return 1
}

# --------------------------------------------------------------
# CONFIGURAR APACHE2
# --------------------------------------------------------------
_configure_apache() {
    local PORT="$1" VERSION="$2"

    log_inf "Configurando Apache2 en puerto $PORT..."
    systemctl stop apache2 >/dev/null 2>&1

    # ports.conf
    if [[ -f /etc/apache2/ports.conf ]]; then
        sed -i "s/^Listen .*/Listen $PORT/" /etc/apache2/ports.conf
        grep -q "^Listen" /etc/apache2/ports.conf || echo "Listen $PORT" >> /etc/apache2/ports.conf
    else
        mkdir -p /etc/apache2
        echo "Listen $PORT" > /etc/apache2/ports.conf
    fi

    # VirtualHost
    if [[ -f /etc/apache2/sites-available/000-default.conf ]]; then
        sed -i "s/<VirtualHost \*:[0-9]*>/<VirtualHost *:$PORT>/" \
            /etc/apache2/sites-available/000-default.conf
    fi

    mkdir -p /var/www/html
    chown -R www-data:www-data /var/www/html
    chmod -R 750 /var/www/html

    create_index "Apache2" "$VERSION" "$PORT" "/var/www/html"
    harden_apache

    log_inf "Verificando configuracion Apache2..."
    apache2ctl configtest 2>&1 | grep -v "^$"

    systemctl enable apache2 >/dev/null 2>&1
    systemctl start apache2
    log_ok "Apache2 configurado"
}

# --------------------------------------------------------------
# CONFIGURAR NGINX
# --------------------------------------------------------------
_configure_nginx() {
    local PORT="$1" VERSION="$2"

    log_inf "Configurando Nginx en puerto $PORT..."
    systemctl stop nginx >/dev/null 2>&1

    mkdir -p /etc/nginx/snippets

    # Reescribir default site completo
    cat > /etc/nginx/sites-available/default <<CONF
server {
    listen ${PORT} default_server;
    listen [::]:${PORT} default_server;

    root /var/www/html;
    index index.html index.htm;
    server_name _;

    include snippets/seguridad.conf;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ /\. {
        deny all;
    }
}
CONF

    ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default 2>/dev/null

    mkdir -p /var/www/html
    chown -R www-data:www-data /var/www/html
    chmod -R 750 /var/www/html

    create_index "Nginx" "$VERSION" "$PORT" "/var/www/html"
    harden_nginx

    log_inf "Verificando configuracion Nginx..."
    if ! nginx -t 2>&1; then
        log_err "Error en config Nginx. Abortando."
        return 1
    fi

    systemctl enable nginx >/dev/null 2>&1
    systemctl start nginx
    log_ok "Nginx configurado"
}

# --------------------------------------------------------------
# PREGUNTAR REINSTALACION
# --------------------------------------------------------------
ask_reinstall() {
    local SVC="$1" VER_EXISTENTE="$2"

    echo ""
    log_war "Ya existe $SVC instalado -> $VER_EXISTENTE"
    log_war "Reinstalar borrara todo rastro anterior (recomendado para evitar corrupcion)."
    echo ""

    local RESP
    while true; do
        read -rp "  Reinstalar? [s/N]: " RESP
        RESP="${RESP,,}"
        RESP="${RESP//[^a-z]/}"
        case "$RESP" in
            s|si|y|yes) return 0 ;;
            n|no|"")    return 1 ;;
            *)          log_war "Responde s o n." ;;
        esac
    done
}

# --------------------------------------------------------------
# INSTALAR PAQUETE (con salida visible, sin -qq)
# --------------------------------------------------------------
apt_install() {
    local PKG="$1" VER="$2"

    log_inf "Instalando $PKG..."
    wait_for_apt

    local RET

    if [[ "$VER" == "latest" ]]; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y "$PKG"
        RET=$?
    else
        DEBIAN_FRONTEND=noninteractive apt-get install -y "${PKG}=${VER}"
        RET=$?
        if [[ $RET -ne 0 ]]; then
            log_war "Version exacta no disponible. Instalando la ultima..."
            wait_for_apt
            DEBIAN_FRONTEND=noninteractive apt-get install -y "$PKG"
            RET=$?
        fi
    fi

    return $RET
}

# --------------------------------------------------------------
# DEPLOY APACHE2 / NGINX
# --------------------------------------------------------------
deploy_service() {
    local SERVICE="$1"

    echo ""
    log "=== DESPLIEGUE DE ${SERVICE^^} ==="

    # 1. Verificar instalacion existente
    local VER_EXISTENTE
    VER_EXISTENTE=$(check_existing "$SERVICE")

    if [[ -n "$VER_EXISTENTE" ]]; then
        if ask_reinstall "$SERVICE" "$VER_EXISTENTE"; then
            purge_service "$SERVICE"
        else
            log_inf "Instalacion cancelada."
            sleep 1
            return 0
        fi
    fi

    # 2. Version
    local VERSION
    select_version "$SERVICE" VERSION

    # 3. Puerto
    local PORT
    ask_port PORT "Puerto de escucha para $SERVICE"

    # 4. Instalar (salida visible)
    if ! apt_install "$SERVICE" "$VERSION"; then
        log_err "Fallo la instalacion de $SERVICE."
        log_err "Comando manual: apt-get install -y $SERVICE"
        return 1
    fi

    # Obtener version real instalada
    VERSION=$(dpkg -l "$SERVICE" 2>/dev/null | awk '/^ii/{print $3}' | head -1)
    [[ -z "$VERSION" ]] && VERSION="desconocida"
    log_ok "$SERVICE instalado: $VERSION"

    # 5. Configurar
    if [[ "$SERVICE" == "apache2" ]]; then
        _configure_apache "$PORT" "$VERSION" || return 1
    else
        _configure_nginx  "$PORT" "$VERSION" || return 1
    fi

    # 6. Firewall
    ufw allow "${PORT}/tcp" >/dev/null 2>&1
    log_ok "Puerto $PORT abierto en UFW"

    # 7. Verificar
    if check_service "$SERVICE"; then
        local IP
        IP=$(hostname -I 2>/dev/null | awk '{print $1}')
        echo ""
        log_ok "$SERVICE activo en http://${IP}:${PORT}"
        log_ok "Prueba: curl -I http://${IP}:${PORT}"
    else
        log_err "$SERVICE no inicio. Revisa: journalctl -u $SERVICE -n 30"
        return 1
    fi
}

# --------------------------------------------------------------
# DEPLOY TOMCAT
# --------------------------------------------------------------
deploy_tomcat() {
    echo ""
    log "=== DESPLIEGUE DE APACHE TOMCAT ==="

    # 1. Verificar existente
    local VER_EXISTENTE
    VER_EXISTENTE=$(check_existing "tomcat")

    if [[ -n "$VER_EXISTENTE" ]]; then
        if ask_reinstall "tomcat" "$VER_EXISTENTE"; then
            purge_service "tomcat"
        else
            log_inf "Instalacion cancelada."
            sleep 1
            return 0
        fi
    fi

    # 2. Version
    echo ""
    echo "  Versiones disponibles de Tomcat:"
    echo "  1) 10.1.26  <- Mas reciente (Java 11+)"
    echo "  2) 10.1.18  <- Estable (Java 11+)"
    echo "  3) 9.0.84   <- LTS anterior (Java 8+)"
    echo ""

    local VER_SEL VER MAJOR
    while true; do
        read -rp "  Seleccione version [1-3]: " VER_SEL
        VER_SEL="${VER_SEL//[^0-9]/}"
        [[ "$VER_SEL" =~ ^[1-3]$ ]] && break
        log_war "Opcion invalida."
    done

    case "$VER_SEL" in
        1) VER="10.1.26"; MAJOR="10" ;;
        2) VER="10.1.18"; MAJOR="10" ;;
        3) VER="9.0.84";  MAJOR="9"  ;;
    esac
    log_ok "Version seleccionada: $VER"

    # 3. Puerto
    local PORT
    ask_port PORT "Puerto de escucha para Tomcat"

    # 4. Java
    log_inf "Instalando Java..."
    wait_for_apt
    DEBIAN_FRONTEND=noninteractive apt-get install -y default-jdk wget tar 2>&1 | tail -5

    if ! command -v java &>/dev/null; then
        log_err "Java no se instalo. Abortando."
        return 1
    fi
    log_ok "Java: $(java -version 2>&1 | head -1)"

    # 5. Usuario dedicado
    if ! id tomcat &>/dev/null; then
        useradd -m -U -d /opt/tomcat -s /bin/false tomcat
        log_ok "Usuario tomcat creado"
    fi

    # 6. Descargar
    local FILE="/tmp/tomcat-${VER}.tar.gz"
    local URL="https://archive.apache.org/dist/tomcat/tomcat-${MAJOR}/v${VER}/bin/apache-tomcat-${VER}.tar.gz"

    log_inf "Descargando Tomcat $VER..."
    rm -f "$FILE"
    wget --timeout=90 --tries=3 --progress=dot:mega -O "$FILE" "$URL"

    if [[ ! -s "$FILE" ]]; then
        log_err "Descarga fallida. Verifica conexion a internet."
        rm -f "$FILE"
        return 1
    fi
    log_ok "Descarga OK ($(du -sh "$FILE" | cut -f1))"

    # 7. Extraer
    log_inf "Extrayendo en /opt/tomcat..."
    rm -rf /opt/tomcat
    mkdir -p /opt/tomcat

    if ! tar -xzf "$FILE" -C /opt/tomcat --strip-components=1; then
        log_err "Error extrayendo tar.gz"
        rm -f "$FILE"
        return 1
    fi
    rm -f "$FILE"

    # 8. Permisos
    chown -R tomcat:tomcat /opt/tomcat
    chmod -R 750 /opt/tomcat
    chmod -R 755 /opt/tomcat/webapps
    log_ok "Permisos aplicados"

    # 9. Puerto
    sed -i "s/port=\"[0-9]*\" protocol=\"HTTP\/1.1\"/port=\"${PORT}\" protocol=\"HTTP\/1.1\"/" \
        /opt/tomcat/conf/server.xml
    log_ok "Puerto $PORT configurado en server.xml"

    # 10. Index
    create_index "Tomcat" "$VER" "$PORT" "/opt/tomcat/webapps/ROOT"
    chown -R tomcat:tomcat /opt/tomcat/webapps/ROOT

    # 11. JAVA_HOME
    local JH
    JH=$(dirname "$(dirname "$(readlink -f "$(which java)")")")
    log_inf "JAVA_HOME: $JH"

    # 12. Servicio systemd
    cat > /etc/systemd/system/tomcat.service <<EOF
[Unit]
Description=Apache Tomcat ${VER}
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=${JH}"
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
EOF

    systemctl daemon-reload
    systemctl enable tomcat >/dev/null 2>&1
    systemctl start tomcat

    # 13. Firewall
    ufw allow "${PORT}/tcp" >/dev/null 2>&1
    log_ok "Puerto $PORT abierto en UFW"

    # 14. Verificar
    log_inf "Esperando arranque de Tomcat (~15s)..."
    sleep 12

    if check_service "tomcat"; then
        local IP
        IP=$(hostname -I 2>/dev/null | awk '{print $1}')
        echo ""
        log_ok "Tomcat $VER activo en http://${IP}:${PORT}"
        log_ok "Prueba: curl -I http://${IP}:${PORT}"
    else
        log_err "Tomcat no inicio. Revisa: journalctl -u tomcat -n 30"
        return 1
    fi
}