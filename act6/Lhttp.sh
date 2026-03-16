#!/bin/bash
# ==========================================================
# MODULE: Lhttp.sh
# ==========================================================

# 1. Preparación de herramientas necesarias
function prepare_environment() {
    echo "[*] Verificando dependencias del sistema..."
    apt-get update -qq
    apt-get install -y lsof curl ufw gawk sed coreutils > /dev/null
}

# 2. Validación de puertos (Requerimiento de seguridad)
function validate_port() {
    local PORT=$1
    # Validar que sea número
    if [[ ! $PORT =~ ^[0-9]+$ ]]; then return 1; fi
    # Puertos reservados o comunes ocupados
    if [[ " 22 3389 3306 5432 " =~ " $PORT " ]]; then
        echo "[!] Puerto reservado para sistema."
        return 1
    fi
    # Verificar si está en uso
    if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null ; then
        echo "[!] Puerto $PORT ya está siendo utilizado por otro servicio."
        return 1
    fi
    return 0
}

# 3. Consulta dinámica de versiones (Requerimiento apt-cache)
function get_versions() {
    local SERVICE=$1
    echo "[*] Consultando versiones disponibles para $SERVICE..."
    # Extraemos solo la columna de versiones de apt-cache madison
    apt-cache madison $SERVICE | awk '{print $3}'
}

# 4. Creación de página index personalizada
function create_custom_index() {
    local SERVICE=$1
    local VERSION=$2
    local PORT=$3
    local PATH_DIR=$4
    
    cat <<EOF > "${PATH_DIR}/index.html"
<html>
<head><title>Servidor Proprovisionado</title></head>
<body>
    <h1>Servidor: $SERVICE</h1>
    <p><b>Versión:</b> $VERSION</p>
    <p><b>Puerto:</b> $PORT</p>
    <hr>
    <p>Aprovisionamiento Automatizado - Práctica 6</p>
</body>
</html>
EOF
}

# 5. Despliegue de Apache y Nginx
function deploy_service() {
    local SERVICE=$1
    
    # Obtener versiones dinámicamente
    VERSIONS=($(get_versions $SERVICE))
    echo "Versiones encontradas:"
    select VERSION in "${VERSIONS[@]}"; do
        if [[ -n "$VERSION" ]]; then break; fi
    done

    # Pedir puerto
    read -p "Defina el puerto de escucha: " PUERTO
    until validate_port $PUERTO; do
        read -p "Intente con otro puerto: " PUERTO
    done

    # Instalación silenciosa
    echo "[+] Instalando $SERVICE ($VERSION)..."
    apt-get install -y "${SERVICE}=${VERSION}" > /dev/null

    # Configuración de puerto y Hardening
    if [[ "$SERVICE" == "apache2" ]]; then
        # Cambio de puerto
        sed -i "s/Listen 80/Listen $PUERTO/g" /etc/apache2/ports.conf
        sed -i "s/<VirtualHost \*:80>/<VirtualHost \*:$PUERTO>/g" /etc/apache2/sites-available/000-default.conf
        
        # Hardening (Ocultar versión y Security Headers)
        sed -i "s/ServerTokens OS/ServerTokens Prod/" /etc/apache2/conf-enabled/security.conf
        sed -i "s/ServerSignature On/ServerSignature Off/" /etc/apache2/conf-enabled/security.conf
        
        # Inyectar Security Headers
        a2enmod headers > /dev/null
        echo "Header set X-Frame-Options \"SAMEORIGIN\"" >> /etc/apache2/apache2.conf
        echo "Header set X-Content-Type-Options \"nosniff\"" >> /etc/apache2/apache2.conf
        
        create_custom_index "Apache2" "$VERSION" "$PUERTO" "/var/www/html"
        systemctl restart apache2
        
    elif [[ "$SERVICE" == "nginx" ]]; then
        # Cambio de puerto
        sed -i "s/listen 80 default_server;/listen $PUERTO default_server;/g" /etc/nginx/sites-available/default
        
        # Hardening
        sed -i "s/# server_tokens off;/server_tokens off;/g" /etc/nginx/nginx.conf
        
        # Security Headers
        sed -i "/http {/a \    add_header X-Frame-Options SAMEORIGIN;\n    add_header X-Content-Type-Options nosniff;" /etc/nginx/nginx.conf
        
        create_custom_index "Nginx" "$VERSION" "$PUERTO" "/var/www/html"
        systemctl restart nginx
    fi

    # Firewall
    ufw allow "$PUERTO/tcp" > /dev/null
    echo "[OK] Servicio $SERVICE activo en puerto $PUERTO."
    read -p "Presione Enter para continuar..."
}

# 6. Despliegue de Tomcat (Manejo de Binarios)
function deploy_tomcat() {
    echo "[*] Preparando Tomcat vía Binario..."
    
    read -p "Defina puerto para Tomcat (ej. 8080): " PUERTO
    until validate_port $PUERTO; do
        read -p "Puerto ocupado. Elija otro: " PUERTO
    done

    # Usuario dedicado (Requerimiento)
    if ! id "tomcat" &>/dev/null; then
        useradd -m -U -d /opt/tomcat -s /bin/false tomcat
    fi

    # Descarga de la última versión LTS (Tomcat 10)
    local VERSION="10.1.18" # Podría hacerse dinámico con el API de Apache
    wget -q "https://archive.apache.org/dist/tomcat/tomcat-10/v${VERSION}/bin/apache-tomcat-${VERSION}.tar.gz" -P /tmp
    
    tar -xf "/tmp/apache-tomcat-${VERSION}.tar.gz" -C /opt/tomcat --strip-components=1
    chown -R tomcat:tomcat /opt/tomcat
    chmod -R 755 /opt/tomcat

    # Configuración de puerto en server.xml
    sed -i "s/Connector port=\"8080\"/Connector port=\"$PUERTO\"/g" /opt/tomcat/conf/server.xml

    # Index personalizado
    create_custom_index "Apache Tomcat" "$VERSION" "$PUERTO" "/opt/tomcat/webapps/ROOT"

    ufw allow "$PUERTO/tcp"
    echo "[OK] Tomcat instalado en /opt/tomcat. Inicie con /opt/tomcat/bin/startup.sh"
    read -p "Presione Enter para continuar..."
}