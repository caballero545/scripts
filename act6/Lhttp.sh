#!/bin/bash
# ==========================================================
# MODULE: Lhttp.sh - Provisión y Hardening
# ==========================================================

function prepare_environment() {
    echo "[*] Limpiando bloqueos de apt y preparando herramientas..."
    sudo rm /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock &>/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y lsof curl ufw gawk sed coreutils apache2-utils > /dev/null
    
    # Configuración básica de Firewall para no perder SSH
    sudo ufw allow 22/tcp > /dev/null
    echo "y" | sudo ufw enable > /dev/null
}

function validate_port() {
    local PORT=$1
    if [[ ! $PORT =~ ^[0-9]+$ ]]; then return 1; fi
    
    # Puertos prohibidos (Rúbrica: restringir puertos reservados)
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
    # Rúbrica: Consulta dinámica mediante apt-cache madison
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
    # Rúbrica: Permisos limitados al directorio
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

    echo "[+] Instalando $SERVICE ($VERSION) y dependencias..."
    # Fix para el error de dependencias: usamos -f y --allow-downgrades si es necesario
    sudo apt-get install -y --allow-downgrades "${SERVICE}=${VERSION}" > /dev/null 2>&1

    if [ $? -ne 0 ]; then
        echo "[!] Fallo de dependencias detectado. Forzando instalación..."
        sudo apt-get install -y -f > /dev/null
    fi

    # --- HARDENING Y CONFIGURACIÓN ---
    if [[ "$SERVICE" == "apache2" ]]; then
        # Cambio de puerto (sed)
        sudo sed -i "s/Listen 80/Listen $PUERTO/g" /etc/apache2/ports.conf
        sudo sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:$PUERTO>/g" /etc/apache2/sites-available/000-default.conf
        
        # Ocultar versión (ServerTokens Prod)
        sudo sed -i "s/ServerTokens OS/ServerTokens Prod/" /etc/apache2/conf-enabled/security.conf
        sudo sed -i "s/ServerSignature On/ServerSignature Off/" /etc/apache2/conf-enabled/security.conf
        
        # Headers y Bloqueo de Métodos (TRACE/DELETE)
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
        sudo sed -i "s/listen 80/listen $PUERTO/g" /etc/nginx/sites-available/default
        sudo sed -i "s/# server_tokens off;/server_tokens off;/g" /etc/nginx/nginx.conf
        
        # Inyectar Headers en el bloque HTTP
        sudo sed -i "/http {/a \    add_header X-Frame-Options SAMEORIGIN;\n    add_header X-Content-Type-Options nosniff;" /etc/nginx/nginx.conf
        
        create_custom_index "Nginx" "$VERSION" "$PUERTO" "/var/www/html"
        sudo systemctl restart nginx
    fi

    sudo ufw allow "$PUERTO/tcp" > /dev/null
    echo -e "\n[OK] Despliegue completado con éxito."
    read -p "Presione Enter para continuar..."
}

function deploy_tomcat() {
    echo "[*] Instalando Tomcat vía Binario (Usuario dedicado)..."
    read -p "Puerto para Tomcat: " PUERTO
    until validate_port "$PUERTO"; do
        read -p "Puerto ocupado. Elija otro: " PUERTO
    done

    # Rúbrica: Usuario dedicado con permisos limitados
    if ! id "tomcat" &>/dev/null; then
        sudo useradd -m -U -d /opt/tomcat -s /bin/false tomcat
    fi

    local T_VER="10.1.18"
    sudo wget -q "https://archive.apache.org/dist/tomcat/tomcat-10/v${T_VER}/bin/apache-tomcat-${T_VER}.tar.gz" -P /tmp
    sudo tar -xf "/tmp/apache-tomcat-${T_VER}.tar.gz" -C /opt/tomcat --strip-components=1
    
    sudo chown -R tomcat:tomcat /opt/tomcat
    sudo chmod -R 755 /opt/tomcat
    
    # Cambio de puerto en el XML
    sudo sed -i "s/Connector port=\"8080\"/Connector port=\"$PUERTO\"/g" /opt/tomcat/conf/server.xml
    
    create_custom_index "Apache Tomcat" "$T_VER" "$PUERTO" "/opt/tomcat/webapps/ROOT"
    sudo ufw allow "$PUERTO/tcp"
    echo "[OK] Tomcat listo en puerto $PUERTO."
    read -p "Presione Enter para continuar..."
}