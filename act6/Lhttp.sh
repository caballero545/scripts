#!/bin/bash
# ==========================================================
# MODULE: Lhttp.sh - Provision y Hardening Ultra-Robusto
# ==========================================================

function wait_for_apt() {
    echo "[*] Verificando que el gestor de paquetes este libre..."
    # Ciclo de espera mas agresivo para evitar el error de "lock-frontend"
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
        echo "[-] Sistema ocupado por actualizaciones automaticas. Reintentando en 5s..."
        sleep 5
    done
}

function prepare_environment() {
    wait_for_apt
    echo "[+] Limpiando cache y actualizando repositorios..."
    sudo apt-get clean
    sudo apt-get update -y
    
    echo "[+] Instalando herramientas base..."
    sudo apt-get install -y lsof curl ufw gawk sed coreutils apache2-utils
    
    sudo ufw allow 22/tcp > /dev/null
    echo "y" | sudo ufw enable > /dev/null
}

function validate_port() {
    local PORT=$1
    if [[ ! $PORT =~ ^[0-9]+$ ]] || [ "$PORT" -gt 65535 ]; then 
        echo "[!] Puerto invalido (debe ser 1-65535)."
        return 1 
    fi
    local RESERVADOS=(21 22 25 53 110 143 443 3306 3389 5432)
    for p in "${RESERVADOS[@]}"; do
        if [[ "$PORT" == "$p" ]]; then
            echo "[!] El puerto $p es critico del sistema. Elige otro."
            return 1
        fi
    done
    if sudo lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null ; then
        echo "[!] El puerto $PORT ya esta ocupado."
        return 1
    fi
    return 0
}

function get_versions() {
    local SERVICE=$1
    apt-cache madison "$SERVICE" | awk '{print $3}' | sort -u
}

function create_custom_index() {
    local SERVICE=$1; local VERSION=$2; local PORT=$3; local ROOT_DIR=$4
    sudo mkdir -p "$ROOT_DIR"
    sudo bash -c "cat <<EOF > ${ROOT_DIR}/index.html
<html>
<body style='font-family: sans-serif; text-align: center; background: #eceff1;'>
    <div style='margin-top: 100px; border: 2px solid #607d8b; display: inline-block; padding: 30px; background: white; border-radius: 10px;'>
        <h1 style='color: #263238;'>Servidor: $SERVICE - Version: $VERSION - Puerto: $PORT</h1>
        <hr>
        <p style='color: #78909c;'>FES Aragon - Provision Automatica</p>
    </div>
</body>
</html>
EOF"
    
    # Rúbrica: Permisos 750 (Dueño todo, Grupo lectura, Otros nada)
    if [[ "$SERVICE" == *"Tomcat"* ]]; then
        sudo chown -R tomcat:tomcat "$ROOT_DIR"
    else
        sudo chown -R www-data:www-data "$ROOT_DIR"
    fi
    sudo chmod -R 750 "$ROOT_DIR"
}

function deploy_service() {
    local SERVICE=$1
    echo -e "\n[*] Consultando versiones para $SERVICE..."
    mapfile -t VERSIONS < <(get_versions "$SERVICE")
    
    if [ ${#VERSIONS[@]} -eq 0 ]; then
        echo "[!] No se encontraron versiones."
        read -p "Presione Enter..."
        return 1
    fi

    echo "Seleccione version:"
    select VERSION in "${VERSIONS[@]}"; do
        [[ -n "$VERSION" ]] && break
    done

    read -p "Puerto: " PUERTO
    until validate_port "$PUERTO"; do
        read -p "Elija otro puerto: " PUERTO
    done

    wait_for_apt
    echo "[+] Instalando $SERVICE=$VERSION..."
    if ! sudo apt-get install -y --allow-downgrades "${SERVICE}=${VERSION}"; then
        echo "[!] Fallo la instalacion. Intentando reparar..."
        sudo apt-get install -y -f
        if ! sudo apt-get install -y "$SERVICE"; then
            echo "CRITICO: Fallo total de instalacion."
            read -p "Presione Enter..."
            return 1
        fi
    fi

    # --- CONFIGURACION Y HARDENING ---
    if [[ "$SERVICE" == "apache2" ]]; then
        sudo sed -i "s/Listen 80/Listen $PUERTO/g" /etc/apache2/ports.conf
        sudo sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:$PUERTO>/g" /etc/apache2/sites-available/000-default.conf
        sudo sed -i "s/ServerTokens OS/ServerTokens Prod/" /etc/apache2/conf-enabled/security.conf
        sudo sed -i "s/ServerSignature On/ServerSignature Off/" /etc/apache2/conf-enabled/security.conf
        sudo a2enmod headers > /dev/null
        sudo bash -c "cat <<EOF > /etc/apache2/conf-available/hardening.conf
Header set X-Frame-Options 'SAMEORIGIN'
Header set X-Content-Type-Options 'nosniff'
<Directory /var/www/html>
    <LimitExcept GET POST>
        Require all denied
    </LimitExcept>
</Directory>
EOF"
        sudo a2enconf hardening > /dev/null
        create_custom_index "Apache2" "$VERSION" "$PUERTO" "/var/www/html"
        sudo systemctl restart apache2

    elif [[ "$SERVICE" == "nginx" ]]; then
        [[ -f /etc/nginx/sites-available/default ]] && sudo sed -i "s/listen 80/listen $PUERTO/g" /etc/nginx/sites-available/default
        sudo sed -i "s/# server_tokens off;/server_tokens off;/g" /etc/nginx/nginx.conf
        sudo sed -i "/http {/a \    add_header X-Frame-Options SAMEORIGIN;\n    add_header X-Content-Type-Options nosniff;" /etc/nginx/nginx.conf
        # Bloqueo de metodos en Nginx
        sudo sed -i "/server_name _;/a \    if (\$request_method !~ ^(GET|POST)$ ) { return 405; }" /etc/nginx/sites-available/default
        create_custom_index "Nginx" "$VERSION" "$PUERTO" "/var/www/html"
        sudo systemctl restart nginx
    fi

    if [ "$PUERTO" != "80" ]; then sudo ufw deny 80/tcp > /dev/null; fi
    sudo ufw allow "$PUERTO/tcp" > /dev/null
    echo -e "\n[OK] $SERVICE en puerto $PUERTO con Hardening aplicado."
    read -p "Presione Enter..."
}

function deploy_tomcat() {
    echo "[*] Instalando Tomcat de forma segura..."
    read -p "Puerto: " PUERTO
    until validate_port "$PUERTO"; do read -p "Puerto ocupado: " PUERTO; done
    
    if ! id "tomcat" &>/dev/null; then
        sudo useradd -m -U -d /opt/tomcat -s /bin/false tomcat
    fi

    local T_VER="10.1.18"
    local T_FILE="/tmp/apache-tomcat-${T_VER}.tar.gz"
    
    # Descarga con verificacion de integridad
    echo "[+] Descargando binarios de Tomcat..."
    sudo wget -c -q "https://archive.apache.org/dist/tomcat/tomcat-10/v${T_VER}/bin/apache-tomcat-${T_VER}.tar.gz" -O "$T_FILE"
    
    if [ ! -s "$T_FILE" ]; then
        echo "[!] Error: Descarga fallida o archivo vacio."
        return 1
    fi

    sudo mkdir -p /opt/tomcat
    if ! sudo tar -xf "$T_FILE" -C /opt/tomcat --strip-components=1; then
        echo "[!] Error: El archivo descargado esta corrupto. Borrando..."
        sudo rm -f "$T_FILE"
        return 1
    fi

    sudo chown -R tomcat:tomcat /opt/tomcat
    sudo chmod -R 750 /opt/tomcat
    sudo sed -i "s/Connector port=\"8080\"/Connector port=\"$PUERTO\"/g" /opt/tomcat/conf/server.xml
    # Hardening: Ocultar version en el header Server
    sudo sed -i "s/<Connector port=\"$PUERTO\"/<Connector port=\"$PUERTO\" server=\"Apache\"/g" /opt/tomcat/conf/server.xml

    create_custom_index "Apache Tomcat" "$T_VER" "$PUERTO" "/opt/tomcat/webapps/ROOT"
    
    if [ "$PUERTO" != "8080" ]; then sudo ufw deny 8080/tcp > /dev/null; fi
    sudo ufw allow "$PUERTO/tcp" > /dev/null
    echo "[OK] Tomcat listo y asegurado."
    read -p "Presione Enter..."
}