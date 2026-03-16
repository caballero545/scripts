#!/bin/bash
# ==========================================================
# MODULE: Lhttp.sh - Provisión y Hardening Ultra-Robusto
# ==========================================================

function prepare_environment() {
    echo "[*] Verificando disponibilidad del gestor de paquetes..."
    
    # Espera activa para el lock de apt
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do
        echo "[-] El sistema está ocupado. Reintentando en 5s..."
        sleep 5
    done

    echo "[+] Limpiando caché y actualizando repositorios..."
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
        echo "[!] Puerto inválido (debe ser 1-65535)."
        return 1 
    fi
    local RESERVADOS=(21 22 25 53 110 143 443 3306 3389 5432)
    for p in "${RESERVADOS[@]}"; do
        if [[ "$PORT" == "$p" ]]; then
            echo "[!] El puerto $p es crítico del sistema. Elige otro."
            return 1
        fi
    done
    if sudo lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null ; then
        echo "[!] El puerto $PORT ya está ocupado."
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
        <h1 style='color: #263238;'>Servidor: $SERVICE</h1>
        <p><b>Estado:</b> Desplegado Correctamente</p>
        <p><b>Puerto:</b> $PORT</p>
        <hr>
        <p style='color: #78909c;'>FES Aragón - Provisión Automática</p>
    </div>
</body>
</html>
EOF"
    sudo chown -R www-data:www-data "$ROOT_DIR"
    sudo chmod -R 755 "$ROOT_DIR"
}

function deploy_service() {
    local SERVICE=$1
    echo -e "\n[*] Consultando versiones para $SERVICE..."
    mapfile -t VERSIONS < <(get_versions "$SERVICE")
    
    if [ ${#VERSIONS[@]} -eq 0 ]; then
        echo "[!] No se encontraron versiones en los repositorios."
        read -p "Presione Enter..."
        return 1
    fi

    echo "Seleccione versión:"
    select VERSION in "${VERSIONS[@]}"; do
        [[ -n "$VERSION" ]] && break
    done

    read -p "Puerto (ej. 8080): " PUERTO
    until validate_port "$PUERTO"; do
        read -p "Elija otro puerto: " PUERTO
    done

    echo "[+] Intentando instalar $SERVICE=$VERSION..."
    # Intentamos instalar la versión elegida
    if ! sudo apt-get install -y --allow-downgrades "${SERVICE}=${VERSION}"; then
        echo "[!] Falló la versión específica. Intentando instalar versión por defecto..."
        sudo apt-get install -y -f
        if ! sudo apt-get install -y "$SERVICE"; then
            echo "CRÍTICO: No se pudo instalar $SERVICE de ninguna forma."
            read -p "Presione Enter..."
            return 1
        fi
    fi

    # --- CONFIGURACIÓN ---
    if [[ "$SERVICE" == "apache2" ]]; then
        sudo sed -i "s/Listen 80/Listen $PUERTO/g" /etc/apache2/ports.conf
        sudo sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:$PUERTO>/g" /etc/apache2/sites-available/000-default.conf
        sudo a2enmod headers > /dev/null
        create_custom_index "Apache2" "$VERSION" "$PUERTO" "/var/www/html"
        sudo systemctl restart apache2
    elif [[ "$SERVICE" == "nginx" ]]; then
        [[ -f /etc/nginx/sites-available/default ]] && sudo sed -i "s/listen 80/listen $PUERTO/g" /etc/nginx/sites-available/default
        create_custom_index "Nginx" "$VERSION" "$PUERTO" "/var/www/html"
        sudo systemctl restart nginx
    fi

    sudo ufw allow "$PUERTO/tcp" > /dev/null
    echo -e "\n[OK] $SERVICE funcionando en puerto $PUERTO."
    read -p "Presione Enter..."
}

function deploy_tomcat() {
    # (Se mantiene igual, Tomcat es por binario y suele fallar menos)
    echo "[*] Instalando Tomcat..."
    read -p "Puerto: " PUERTO
    until validate_port "$PUERTO"; do read -p "Puerto: " PUERTO; done
    
    if ! id "tomcat" &>/dev/null; then
        sudo useradd -m -U -d /opt/tomcat -s /bin/false tomcat
    fi

    local T_VER="10.1.18"
    sudo wget -q "https://archive.apache.org/dist/tomcat/tomcat-10/v${T_VER}/bin/apache-tomcat-${T_VER}.tar.gz" -P /tmp
    sudo tar -xf "/tmp/apache-tomcat-${T_VER}.tar.gz" -C /opt/tomcat --strip-components=1
    sudo chown -R tomcat:tomcat /opt/tomcat
    sudo sed -i "s/Connector port=\"8080\"/Connector port=\"$PUERTO\"/g" /opt/tomcat/conf/server.xml
    create_custom_index "Apache Tomcat" "$T_VER" "$PUERTO" "/opt/tomcat/webapps/ROOT"
    sudo ufw allow "$PUERTO/tcp"
    echo "[OK] Tomcat listo."
    read -p "Presione Enter..."
}