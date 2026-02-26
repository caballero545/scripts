# =====================================================================
# SCRIPT DE ADMINISTRACIÓN DE RED PRO - WINDOWS SERVER (FIXED)
# =====================================================================

$global:IP_FIJA = ""
$global:SEGMENTO = ""

# --- FUNCIONES DE VALIDACIÓN ---
function Test-IsValidIP {
    param([string]$ip, [string]$tipo)
    if ($ip -eq "" -and ($tipo -eq "Opcional")) { return $true }
    if ($ip -match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$") {
        if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255" -or $ip -eq "127.0.0.1") {
            Write-Host "[ERROR] IP $ip prohibida." -ForegroundColor Red
            return $false
        }
        return $true
    }
    return $false
}

function Test-IsValidMask {
    param([string]$mask)
    return $mask -match "^(255|254|252|248|240|224|192|128|0)\.(255|254|252|248|240|224|192|128|0)\.(255|254|252|248|240|224|192|128|0)\.(255|254|252|248|240|224|192|128|0)$"
}

# --- 1. INSTALACIÓN ---
function Instalar-Servicios {
    Clear-Host
    Write-Host "[+] Instalando Roles DHCP y DNS..." -ForegroundColor Cyan
    Install-WindowsFeature -Name DHCP, DNS -IncludeManagementTools
    Set-Service -Name DHCPServer, DNS -StartupType Automatic
    Write-Host "[OK] Roles instalados." -ForegroundColor Green
    Read-Host "Presione Enter..."
}

# --- 2. CONFIGURACIÓN DE RED Y DHCP (Lógica +1) ---
function Configurar-RedPrincipal {
    Clear-Host
    Write-Host "--- CONFIGURACIÓN DE RANGO Y RED ---" -ForegroundColor Cyan

    # Auto-detección de Interfaz para evitar errores de nombre
    $iface = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1 -ExpandProperty Name
    Write-Host "[i] Usando interfaz detectada: $iface" -ForegroundColor Gray

    # Rango Inicial
    while ($true) {
        $R_INI = Read-Host "Ingrese inicio de rango (ej. 10.10.10.10)"
        if (Test-IsValidIP $R_INI "Requerido") { break }
    }

    # Rango Final
    while ($true) {
        $R_FIN = Read-Host "Ingrese fin de rango (ej. 10.10.10.20)"
        if (Test-IsValidIP $R_FIN "Requerido") { break }
    }

    # LÓGICA DE SEGMENTO Y SUMA +1
    $global:IP_FIJA = $R_INI
    $parts = $R_INI.Split('.')
    $global:SEGMENTO = "$($parts[0]).$($parts[1]).$($parts[2])"
    
    # IMPORTANTE: Convertir a [int] para evitar errores de concatenación
    $OctIni = [int]$parts[3]
    $OctFin = [int]$R_FIN.Split('.')[3]
    
    $DHCP_START = "$global:SEGMENTO.$($OctIni + 1)"
    $DHCP_END = "$global:SEGMENTO.$($OctFin + 1)"

    # Máscara
    while ($true) {
        $MASK = Read-Host "Máscara [Enter para 255.255.255.0]"
        if ($MASK -eq "") { $MASK = "255.255.255.0"; break }
        if (Test-IsValidMask $MASK) { break }
    }

    $LEASE_STR = Read-Host "Tiempo de concesión en segundos (ej. 3600)"
    $LEASE = [TimeSpan]::FromSeconds([int]$LEASE_STR)

    # --- APLICAR CAMBIOS ---
    Write-Host "[!] Limpiando IPs previas y aplicando $global:IP_FIJA..." -ForegroundColor Yellow
    Remove-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias $iface -IPAddress $global:IP_FIJA -PrefixLength 24 -ErrorAction SilentlyContinue
    
    # Evitar que se pierda el internet: Forwarders y DNS local
    Set-DnsClientServerAddress -InterfaceAlias $iface -ServerAddresses ("127.0.0.1")
    Add-DnsServerForwarder -IPAddress "8.8.8.8" -Force -ErrorAction SilentlyContinue

    # Configurar DHCP
    Remove-DhcpServerv4Scope -ScopeId "$global:SEGMENTO.0" -Force -ErrorAction SilentlyContinue
    Add-DhcpServerv4Scope -Name "Red_Examen" -StartRange $DHCP_START -EndRange $DHCP_END -SubnetMask $MASK -LeaseDuration $LEASE
    
    # Opción 6 del DHCP: El propio servidor es el DNS de los clientes
    Set-DhcpServerv4OptionValue -OptionId 6 -Value $global:IP_FIJA

    Restart-Service DHCPServer, DNS
    Write-Host "`n[OK] CONFIGURACIÓN COMPLETADA" -ForegroundColor Green
    Write-Host "    - IP Servidor: $global:IP_FIJA"
    Write-Host "    - DHCP (+1): $DHCP_START hasta $DHCP_END"
    Read-Host "Presione Enter..."
}

# --- 3. DOMINIOS ---
function Add-Dominio {
    Clear-Host
    if ($global:IP_FIJA -eq "") { Write-Host "Error: Configure red primero." -ForegroundColor Red; return }
    $DOM = Read-Host "Nombre del dominio (ej. jala.com)"
    if (Get-DnsServerZone -Name $DOM -ErrorAction SilentlyContinue) {
        Write-Host "El dominio ya existe." -ForegroundColor Red
    } else {
        Add-DnsServerPrimaryZone -Name $DOM -ZoneFile "$DOM.dns"
        Add-DnsServerResourceRecordA -Name "@" -IPv4Address $global:IP_FIJA -ZoneName $DOM
        Add-DnsServerResourceRecordA -Name "ns" -IPv4Address $global:IP_FIJA -ZoneName $DOM
        Write-Host "Dominio $DOM creado." -ForegroundColor Green
    }
    Read-Host "Enter..."
}

# --- MENU SIMPLIFICADO ---
while ($true) {
    cls
    Write-Host "--- ADMIN RED WINDOWS SERVER ---" -ForegroundColor Cyan
    Write-Host "IP: $global:IP_FIJA | Segmento: $global:SEGMENTO.0" -ForegroundColor Gray
    Write-Host "1. Instalar Roles"
    Write-Host "2. Configurar Red/DHCP (Lógica +1)"
    Write-Host "3. Añadir Dominio"
    Write-Host "4. Status"
    Write-Host "5. Salir"
    $op = Read-Host "Seleccione"
    switch ($op) {
        "1" { Instalar-Servicios }
        "2" { Configurar-RedPrincipal }
        "3" { Add-Dominio }
        "4" { 
            Get-Service DHCPServer, DNS | Select-Object Name, Status
            Get-DhcpServerv4Scope | Select-Object ScopeId, StartRange, EndRange
            Read-Host "Enter..."
        }
        "5" { exit }
    }
}