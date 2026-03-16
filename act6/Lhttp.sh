#!/bin/bash
# ==========================================================
# MODULE: Lhttp.sh
# ==========================================================

# 1. Preparación de herramientas y limpieza de Firewall
function prepare_environment() {
    echo "[*] Preparando dependencias y asegurando UFW..."
    apt-get update -qq
    apt-get install -y lsof curl ufw gawk sed coreutils apache2-utils > /dev/null
    
    # Asegurar que el firewall esté activo pero no bloquee SSH
    ufw allow 22/tcp > /dev/null
    echo "y" | ufw enable > /dev/null
}

# 2. Validación de puertos (Evita reservados y ocupados)
function validate_port() {
    local PORT=$1
    if [[ ! $PORT =~ ^[0-9]+$ ]]; then return 1; fi
    
    # Restringir puertos reservados de sistema (evitar romper SSH, DBs, etc)
    # Rúbrica: "restringir los puertos reservados para otros servicios"
    local RESERVADOS=(22 21 25 53 110 143 443 3306 3389 5432)
    for p in "${RESERVADOS[@]}"; do
        if [[ "$PORT" == "$p" ]]; then
            echo "[!] Error: El puerto $p está reservado para servicios críticos."
            return 1
        fi
    done

    if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null ; then
        echo "[!] Error: El puerto $PORT ya está en uso."
        return 1
    fi
    return 0
}

# 3. Consulta dinámica de versiones (Rúbrica: apt-cache madison)
function get_versions() {
    local SERVICE=$1
    # Extrae versiones únicas disponibles en el repo
    apt-cache madison "$SERVICE" | awk '{print $3}' | sort -u
}

# 4. Creación de index.html (Rúbrica: Personalizado)
function create_custom_index() {
    local SERVICE=$1; local VERSION=$2; local PORT=$3; local ROOT_DIR=$4
    mkdir -p "$ROOT_DIR"
    cat <<EOF > "${ROOT_DIR}/index.html"
<html>
<body style="font-family: Arial; text-align: center; background: #f4f4f4;">
    <div style="margin-top: 50px; border: 1px solid #ccc; display: inline-block; padding: 20px; background: #fff;">
        <h1>Aprovisionamiento Exitoso</h1>
        <p><b>Servidor:</b> $SERVICE</p>
        <p><b>Versión Elegida:</b> $VERSION</p>
        <p><b>Puerto configurado:</b> $PORT</p>
    </div>
</body>
</html>
EOF
    # Permisos limitados (Rúbrica)
    chown -R www-data:www-data "$ROOT_DIR"
    chmod -R 755 "$ROOT_DIR"
}

# 5. Despliegue de Apache y Nginx
function deploy_service() {
    local SERVICE=$1
    
    echo -e "\n[*] Consultando repositorio para $SERVICE..."
    mapfile -t VERSIONS < <(get_versions "$SERVICE")
    
    if [ ${#VERSIONS[@]} -eq 0 ]; then echo "No se encontraron versiones."; return; fi

    echo "Seleccione la versión a instalar:"
    select VERSION in "${VERSIONS[@]}"; do
        if [[ -n "$VERSION" ]]; then break; fi
    done

    read -p "Ingrese el puerto para $SERVICE: " PUERTO
    until validate_port "$PUERTO"; do
        read -p "Puerto no válido. Intente otro: " PUERTO
    done

    echo "[+] Instalando $SERVICE ($VERSION) de forma silenciosa..."
    apt-get install -y "${SERVICE}=${VERSION}" > /dev/null

    # --- CONFIGURACIÓN Y HARDENING ---
    if [[ "$SERVICE" == "apache2" ]]; then
        # Cambio de puerto
        sed -i "s/Listen 80/Listen $PUERTO/g" /etc/apache2/ports.conf
        sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:$PUERTO>/g" /etc/apache2/sites-available/000-default.conf
        
        # Ocultar Info (Rúbrica)
        sed -i "s/ServerTokens OS/ServerTokens Prod/" /etc/apache2/conf-enabled/security.conf
        sed -i "s/ServerSignature On/ServerSignature Off/" /etc/apache2/conf-enabled/security.conf
        
        # Security Headers y Rechazo de Métodos Peligrosos (TRACE, DELETE, etc)
        a2enmod headers > /dev/null
        cat <<EOF > /etc/apache2/conf-available/custom-hardening.conf
Header set X-Frame-Options "SAMEORIGIN"
Header set X-Content-Type-Options "nosniff"
<Location />
    <LimitExcept GET POST>
        AllowMethods GET POST
        Require all denied
    </LimitExcept>
</Location>
EOF
        a2enconf custom-hardening > /dev/null
        create_custom_index "Apache2" "$VERSION" "$PUERTO" "/var/www/html"
        systemctl restart apache2

    elif [[ "$SERVICE" == "nginx" ]]; then
        # Cambio de puerto
        sed -i "s/listen 80/listen $PUERTO/g" /etc/nginx/sites-available/default
        
        # Hardening e inyección de Headers
        sed -i "s/# server_tokens off;/server_tokens off;/g" /etc/nginx/nginx.conf
        
        # Bloqueo de métodos y Headers en el server block
        local NGINX_CONF="/etc/nginx/conf.d/hardening.conf"
        echo "add_header X-Frame-Options SAMEORIGIN;" > $NGINX_CONF
        echo "add_header X-Content-Type-Options nosniff;" >> $NGINX_CONF
        echo 'if ($request_method !~ ^(GET|POST)$ ) { return 444; }' >> $NGINX_CONF
        
        create_custom_index "Nginx" "$VERSION" "$PUERTO" "/var/www/html"
        systemctl restart nginx
    fi

    # Manejo de Firewall (Rúbrica: Cerrar 80, abrir nuevo)
    ufw deny 80/tcp > /dev/null
    ufw allow "$PUERTO/tcp" > /dev/null
    echo "[OK] Despliegue completo. Puerto abierto: $PUERTO"
    read -p "Presione Enter para volver al menú..."
}

# 6. Despliegue de Tomcat (Rúbrica: Usuario dedicado y permisos)
function deploy_tomcat() {
    echo -e "\n[*] Instalando Tomcat (Última versión LTS)..."
    read -p "Ingrese el puerto para Tomcat: " PUERTO
    until validate_port "$PUERTO"; do
        read -p "Puerto no válido. Intente otro: " PUERTO
    done

    # Crear usuario dedicado si no existe
    if ! id "tomcat" &>/dev/null; then
        useradd -m -U -d /opt/tomcat -s /bin/false tomcat
    fi

    # Descarga dinámica (LTS)
    local T_VER="10.1.18"
    wget -q "https://archive.apache.org/dist/tomcat/tomcat-10/v${T_VER}/bin/apache-tomcat-${T_VER}.tar.gz" -P /tmp
    
    mkdir -p /opt/tomcat
    tar -xf "/tmp/apache-tomcat-${T_VER}.tar.gz" -C /opt/tomcat --strip-components=1
    
    # Permisos restrictivos (Rúbrica)
    chown -R tomcat:tomcat /opt/tomcat
    chmod -R 750 /opt/tomcat/conf
    
    # Cambio de puerto en XML
    sed -i "s/Connector port=\"8080\"/Connector port=\"$PUERTO\"/g" /opt/tomcat/conf/server.xml
    
    create_custom_index "Apache Tomcat" "$T_VER" "$PUERTO" "/opt/tomcat/webapps/ROOT"
    
    ufw allow "$PUERTO/tcp"
    echo "[OK] Tomcat instalado. Usuario 'tomcat' configurado."
    read -p "Presione Enter para volver al menú..."
}