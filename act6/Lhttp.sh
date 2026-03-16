#!/bin/bash
# ==========================================================
# MODULE: Lhttp.sh - Provisión y Hardening Mejorado
# ==========================================================

function prepare_environment() {
    echo "[*] Verificando disponibilidad del gestor de paquetes..."
    
    # Espera activa si otro proceso (como unattended-upgrades) está usando apt
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do
        echo "[-] El sistema está ocupado con otra instalación. Reintentando en 5s..."
        sleep 5
    done

    echo "[+] Sistema libre. Actualizando repositorios e instalando dependencias..."
    sudo apt-get update -qq
    sudo apt-get install -y lsof curl ufw gawk sed coreutils apache2-utils > /dev/null
    
    # Configuración básica de Firewall
    sudo ufw allow 22/tcp > /dev/null
    echo "y" | sudo ufw enable > /dev/null
}

function validate_port() {
    local PORT=$1
    if [[ ! $PORT =~ ^[0-9]+$ ]]; then return 1; fi
    local RESERVADOS=(21 22 25 53 110 143 443 3306 3389 5432)
    for p in "${RESERVADOS[@]}"; do
        if [[ "$PORT" == "$p" ]]; then
            echo "[!] El puerto $p es crítico del sistema. Elige otro."
            return 1
        fi
    done
    if sudo lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null ; then
        echo "[!] El puerto $PORT ya está ocupado por otro proceso."
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
        <p><b>Versión Instalada:</b> $VERSION</p>
        <p><b>Puerto de Escucha:</b> $PORT</p>
        <hr>
        <p style='color: #78909c;'>Despliegue Automatizado - SSH Mode</p>
    </div>
</body>
</html>
EOF"
    sudo chown -R www-data:www-data "$ROOT_DIR"
    sudo chmod -R 755 "$ROOT_DIR"
}

function deploy_service() {
    local SERVICE=$1
    echo -e "\n[*] Buscando versiones reales para $SERVICE..."
    mapfile -t VERSIONS < <(get_versions "$SERVICE")
    
    echo "Seleccione la versión del repositorio:"
    select VERSION in "${VERSIONS[@]}"; do
        if [[ -n "$VERSION" ]]; then break; fi
    done

    read -p "Defina el puerto (ej. 8080): " PUERTO
    until validate_port "$PUERTO"; do
        read -p "Intente con otro puerto: " PUERTO
    done

    echo "[+] Instalando $SERVICE ($VERSION)..."
    sudo apt-get install -y --allow-downgrades "${SERVICE}=${VERSION}" > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo "[!] Fallo inicial. Intentando reparar dependencias..."
        sudo apt-get install -y -f > /dev/null
    fi

    # VALIDACIÓN: Si el paquete no se instaló, no seguimos con la configuración
    if ! dpkg -s "$SERVICE" >/dev/null 2>&1; then
        echo "CRÍTICO: No se pudo instalar $SERVICE. Revisa tu conexión o repositorios."
        read -p "Presione Enter para continuar..."
        return 1
    fi

    # --- HARDENING Y CONFIGURACIÓN ---
    if [[ "$SERVICE" == "apache2" ]]; then
        sudo sed -i "s/Listen 80/Listen $PUERTO/g" /etc/apache2/ports.conf
        sudo sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:$PUERTO>/g" /etc/apache2/sites-available/000-default.conf
        sudo sed -i "s/ServerTokens OS/ServerTokens Prod/" /etc/apache2/conf-enabled/security.conf
        sudo sed -i "s/ServerSignature On/ServerSignature Off/" /etc/apache2/conf-enabled/security.conf
        sudo a2enmod headers > /dev/null
        sudo bash -c "cat <<EOF > /etc/apache2/conf-available/hardening.conf
Header set X-Frame-Options 'SAMEORIGIN'
Header set X-Content-Type-Options 'nosniff'
<Location />
    <LimitExcept GET POST>
        Deny from all
    </LimitExcept>
</Location>
EOF"
        sudo a2enconf hardening > /dev/null
        create_custom_index "Apache2" "$VERSION" "$PUERTO" "/var/www/html"
        sudo systemctl restart apache2

    elif [[ "$SERVICE" == "nginx" ]]; then
        # Verificamos que el archivo de sitio por defecto exista antes de sed
        if [[ -f /etc/nginx/sites-available/default ]]; then
            sudo sed -i "s/listen 80/listen $PUERTO/g" /etc/nginx/sites-available/default
        fi
        sudo sed -i "s/# server_tokens off;/server_tokens off;/g" /etc/nginx/nginx.conf
        sudo sed -i "/http {/a \    add_header X-Frame-Options SAMEORIGIN;\n    add_header X-Content-Type-Options nosniff;" /etc/nginx/nginx.conf
        create_custom_index "Nginx" "$VERSION" "$PUERTO" "/var/www/html"
        sudo systemctl restart nginx
    fi

    sudo ufw allow "$PUERTO/tcp" > /dev/null
    echo -e "\n[OK] Despliegue de $SERVICE completado con éxito."
    read -p "Presione Enter para continuar..."
}

function deploy_tomcat() {
    echo "[*] Instalando Tomcat vía Binario..."
    read -p "Puerto para Tomcat: " PUERTO
    until validate_port "$PUERTO"; do
        read -p "Puerto ocupado. Elija otro: " PUERTO
    done

    if ! id "tomcat" &>/dev/null; then
        sudo useradd -m -U -d /opt/tomcat -s /bin/false tomcat
    fi

    local T_VER="10.1.18"
    sudo wget -q "https://archive.apache.org/dist/tomcat/tomcat-10/v${T_VER}/bin/apache-tomcat-${T_VER}.tar.gz" -P /tmp
    sudo tar -xf "/tmp/apache-tomcat-${T_VER}.tar.gz" -C /opt/tomcat --strip-components=1
    sudo chown -R tomcat:tomcat /opt/tomcat
    sudo chmod -R 755 /opt/tomcat
    sudo sed -i "s/Connector port=\"8080\"/Connector port=\"$PUERTO\"/g" /opt/tomcat/conf/server.xml
    create_custom_index "Apache Tomcat" "$T_VER" "$PUERTO" "/opt/tomcat/webapps/ROOT"
    sudo ufw allow "$PUERTO/tcp"
    echo "[OK] Tomcat listo en puerto $PUERTO."
    read -p "Presione Enter para continuar..."
}