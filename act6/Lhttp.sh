#!/bin/bash

LOG="/tmp/http_provision.log"

function log(){
    echo -e "$1"
    echo "$(date '+%F %T') | $1" >> $LOG
}

#------------------------------------------
# ESPERAR APT
#------------------------------------------
function wait_for_apt(){
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; do
        sleep 2
    done
}

#------------------------------------------
# REPARAR SISTEMA
#------------------------------------------
function fix_system(){
    rm -f /var/lib/dpkg/lock-frontend
    dpkg --configure -a
    apt-get install -f -y
    apt-get update -y
}

#------------------------------------------
# VALIDAR PUERTO
#------------------------------------------
function validate_port(){
    local P=$1

    [[ ! $P =~ ^[0-9]+$ ]] && return 1
    ((P<1 || P>65535)) && return 1

    local RES=(21 22 25 53 3306 3389)
    for r in "${RES[@]}"; do
        [[ "$P" == "$r" ]] && return 1
    done

    lsof -i :$P >/dev/null && return 1

    return 0
}

#------------------------------------------
# PREPARAR ENTORNO
#------------------------------------------
function prepare_environment(){
    wait_for_apt
    fix_system

    apt-get install -y lsof curl ufw gawk sed apache2-utils

    ufw allow 22/tcp >/dev/null
    echo "y" | ufw enable >/dev/null
}

#------------------------------------------
# CONSULTAR VERSIONES (CLAVE DE LA PRACTICA)
#------------------------------------------
function get_versions(){
    local SERVICE=$1
    apt-cache madison $SERVICE | awk '{print $3}' | sort -u
}

#------------------------------------------
# CREAR INDEX DINAMICO
#------------------------------------------
function create_index(){
    local NAME=$1
    local VERSION=$2
    local PORT=$3
    local ROOT=$4

    mkdir -p $ROOT

    cat > $ROOT/index.html <<EOF
<h1>Servidor: $NAME</h1>
<p>Version: $VERSION</p>
<p>Puerto: $PORT</p>
EOF

    chown -R www-data:www-data $ROOT
    chmod -R 750 $ROOT
}

#------------------------------------------
# HARDENING APACHE
#------------------------------------------
function harden_apache(){

sed -i "s/ServerTokens OS/ServerTokens Prod/" /etc/apache2/conf-enabled/security.conf
sed -i "s/ServerSignature On/ServerSignature Off/" /etc/apache2/conf-enabled/security.conf

a2enmod headers >/dev/null

cat > /etc/apache2/conf-available/seguridad.conf <<EOF
Header always set X-Frame-Options SAMEORIGIN
Header always set X-Content-Type-Options nosniff
TraceEnable Off
EOF

a2enconf seguridad >/dev/null
}

#------------------------------------------
# HARDENING NGINX
#------------------------------------------
function harden_nginx(){

sed -i "s/# server_tokens off;/server_tokens off;/" /etc/nginx/nginx.conf

cat >> /etc/nginx/nginx.conf <<EOF

add_header X-Frame-Options SAMEORIGIN;
add_header X-Content-Type-Options nosniff;
EOF
}

#------------------------------------------
# LIMPIEZA CONTROLADA
#------------------------------------------
function clean_service(){
    local S=$1

    systemctl stop $S 2>/dev/null
    apt-get purge -y ${S}* 2>/dev/null
    apt-get autoremove -y
}

#------------------------------------------
# DEPLOY DINAMICO (APACHE / NGINX)
#------------------------------------------
function deploy_service(){

local SERVICE=$1

echo "[*] Versiones disponibles:"
mapfile -t VERS < <(get_versions $SERVICE)

select VERSION in "${VERS[@]}"; do
    [[ -n "$VERSION" ]] && break
done

read -p "Puerto: " PORT
until validate_port $PORT; do
    read -p "Puerto invalido, otro: " PORT
done

wait_for_apt
fix_system
clean_service $SERVICE

log "[+] Instalando $SERVICE versión $VERSION"

if ! apt-get install -y ${SERVICE}=${VERSION} --allow-downgrades; then
    log "[!] Error versión específica, usando estable..."
    apt-get install -y $SERVICE || return 1
fi

# CONFIGURACION
if [[ "$SERVICE" == "apache2" ]]; then

sed -i "s/Listen 80/Listen $PORT/" /etc/apache2/ports.conf
sed -i "s/<VirtualHost \*:80>/<VirtualHost *:$PORT>/" /etc/apache2/sites-available/000-default.conf

create_index "Apache" "$VERSION" "$PORT" "/var/www/html"
harden_apache

systemctl restart apache2

elif [[ "$SERVICE" == "nginx" ]]; then

sed -i "s/listen 80 default_server;/listen $PORT default_server;/" /etc/nginx/sites-available/default

create_index "Nginx" "$VERSION" "$PORT" "/var/www/html"
harden_nginx

systemctl restart nginx
fi

ufw deny 80/tcp >/dev/null
ufw allow $PORT/tcp >/dev/null

log "[OK] $SERVICE listo en puerto $PORT"
}

#------------------------------------------
# TOMCAT (USUARIO DEDICADO)
#------------------------------------------
function deploy_tomcat(){

read -p "Puerto: " PORT
until validate_port $PORT; do
    read -p "Otro puerto: " PORT
done

fix_system

if ! id tomcat &>/dev/null; then
    useradd -m -U -d /opt/tomcat -s /bin/false tomcat
fi

VER="10.1.18"
FILE="/tmp/tomcat.tar.gz"

wget -q -O $FILE "https://archive.apache.org/dist/tomcat/tomcat-10/v$VER/bin/apache-tomcat-$VER.tar.gz"

rm -rf /opt/tomcat
mkdir -p /opt/tomcat

tar -xf $FILE -C /opt/tomcat --strip-components=1 || return 1

chown -R tomcat:tomcat /opt/tomcat
chmod -R 750 /opt/tomcat

sed -i "s/port=\"8080\"/port=\"$PORT\"/" /opt/tomcat/conf/server.xml

create_index "Tomcat" "$VER" "$PORT" "/opt/tomcat/webapps/ROOT"

ufw deny 8080/tcp >/dev/null
ufw allow $PORT/tcp >/dev/null

log "[OK] Tomcat listo puerto $PORT"
}