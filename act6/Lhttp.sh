#!/bin/bash

#==========================================================
# FUNCIONES CORE ULTRA ROBUSTAS
#==========================================================

LOG="/tmp/provision_http.log"

function log() {
    echo -e "$1"
    echo -e "$(date '+%F %T') | $1" >> $LOG
}

#------------------------------------------
# BLOQUEO DE APT
#------------------------------------------
function wait_for_apt() {
    log "[*] Esperando liberación de APT..."
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
       || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        sleep 3
    done
}

#------------------------------------------
# REPARAR SISTEMA
#------------------------------------------
function fix_system() {
    log "[*] Reparando sistema..."

    rm -f /var/lib/dpkg/lock-frontend
    rm -f /var/lib/apt/lists/lock

    dpkg --configure -a
    apt-get install -f -y
    apt-get clean
    apt-get update -y
}

#------------------------------------------
# LIMPIEZA CONTROLADA (NO DESTRUYE TODO)
#------------------------------------------
function clean_service() {
    local SERVICE=$1

    log "[*] Limpiando $SERVICE..."

    systemctl stop $SERVICE 2>/dev/null
    killall $SERVICE 2>/dev/null

    apt-get purge -y ${SERVICE}* 2>/dev/null
    apt-get autoremove -y
    apt-get autoclean

    case $SERVICE in
        apache2)
            rm -rf /etc/apache2
            ;;
        nginx)
            rm -rf /etc/nginx
            ;;
    esac
}

#------------------------------------------
# VALIDAR PUERTO
#------------------------------------------
function validate_port() {
    local PORT=$1

    if [[ ! $PORT =~ ^[0-9]+$ ]] || [ "$PORT" -gt 65535 ] || [ "$PORT" -lt 1 ]; then
        log "[!] Puerto inválido"
        return 1
    fi

    if lsof -i :$PORT >/dev/null 2>&1; then
        log "[!] Puerto en uso"
        return 1
    fi

    return 0
}

#------------------------------------------
# PREPARAR ENTORNO
#------------------------------------------
function prepare_environment() {
    wait_for_apt
    fix_system

    log "[+] Instalando dependencias base..."
    apt-get install -y lsof curl ufw apache2-utils

    ufw allow 22/tcp >/dev/null
    echo "y" | ufw enable >/dev/null
}

#------------------------------------------
# INDEX SEGURO
#------------------------------------------
function create_index() {
    local SERVICE=$1
    local VERSION=$2
    local PORT=$3
    local ROOT=$4

    mkdir -p $ROOT

    cat > $ROOT/index.html <<EOF
<h1>$SERVICE - $VERSION - Puerto $PORT</h1>
EOF

    chown -R www-data:www-data $ROOT
    chmod -R 750 $ROOT
}

#------------------------------------------
# HARDENING APACHE
#------------------------------------------
function harden_apache() {
    sed -i "s/ServerTokens OS/ServerTokens Prod/" /etc/apache2/conf-enabled/security.conf
    sed -i "s/ServerSignature On/ServerSignature Off/" /etc/apache2/conf-enabled/security.conf

    a2enmod headers >/dev/null

    cat > /etc/apache2/conf-available/seguridad.conf <<EOF
Header always set X-Frame-Options SAMEORIGIN
Header always set X-Content-Type-Options nosniff
EOF

    a2enconf seguridad >/dev/null
}

#------------------------------------------
# HARDENING NGINX
#------------------------------------------
function harden_nginx() {
    sed -i "s/# server_tokens off;/server_tokens off;/" /etc/nginx/nginx.conf
}

#------------------------------------------
# DEPLOY DINAMICO
#------------------------------------------
function deploy_service() {

    local SERVICE=$1

    read -p "Puerto: " PORT
    until validate_port $PORT; do
        read -p "Otro puerto: " PORT
    done

    wait_for_apt
    fix_system
    clean_service $SERVICE

    log "[+] Instalando $SERVICE limpio..."

    if ! apt-get install -y $SERVICE; then
        log "[!] Error instalación, intentando reparación..."
        fix_system
        apt-get install -y $SERVICE || {
            log "[CRITICO] No se pudo instalar $SERVICE"
            return 1
        }
    fi

    #--------------------------------------
    # CONFIGURACION
    #--------------------------------------
    if [[ "$SERVICE" == "apache2" ]]; then

        sed -i "s/Listen 80/Listen $PORT/" /etc/apache2/ports.conf
        sed -i "s/<VirtualHost \*:80>/<VirtualHost *:$PORT>/" /etc/apache2/sites-available/000-default.conf

        create_index "Apache" "stable" "$PORT" "/var/www/html"
        harden_apache

        systemctl daemon-reexec
        systemctl restart apache2

    elif [[ "$SERVICE" == "nginx" ]]; then

        sed -i "s/listen 80 default_server;/listen $PORT default_server;/" /etc/nginx/sites-available/default

        create_index "Nginx" "stable" "$PORT" "/var/www/html"
        harden_nginx

        systemctl restart nginx
    fi

    ufw allow $PORT/tcp >/dev/null

    log "[OK] $SERVICE funcionando en puerto $PORT"
}

#------------------------------------------
# TOMCAT SEGURO
#------------------------------------------
function deploy_tomcat() {

    read -p "Puerto: " PORT
    until validate_port $PORT; do
        read -p "Otro puerto: " PORT
    done

    fix_system

    if ! id tomcat &>/dev/null; then
        useradd -m -U -d /opt/tomcat -s /bin/false tomcat
    fi

    local VER="10.1.18"
    local FILE="/tmp/tomcat.tar.gz"

    wget -q -O $FILE "https://archive.apache.org/dist/tomcat/tomcat-10/v$VER/bin/apache-tomcat-$VER.tar.gz"

    rm -rf /opt/tomcat
    mkdir -p /opt/tomcat

    tar -xf $FILE -C /opt/tomcat --strip-components=1 || {
        log "[ERROR] Tomcat corrupto"
        return 1
    }

    chown -R tomcat:tomcat /opt/tomcat
    chmod -R 750 /opt/tomcat

    sed -i "s/port=\"8080\"/port=\"$PORT\"/" /opt/tomcat/conf/server.xml

    create_index "Tomcat" "$VER" "$PORT" "/opt/tomcat/webapps/ROOT"

    ufw allow $PORT/tcp >/dev/null

    log "[OK] Tomcat listo en puerto $PORT"
}