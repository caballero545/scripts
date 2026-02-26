# =====================================================================
# SCRIPT DE ADMINISTRACIÓN DE RED - MIGRACIÓN LINUX A WINDOWS
# =====================================================================

$global:IP_FIJA = ""
$global:SEGMENTO = ""

# --- FUNCIONES DE VALIDACIÓN (Réplica de Linux) ---

function Test-ValidarIP {
    param([string]$ip)
    if ($ip -match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$") {
        if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255" -or $ip -eq "127.0.0.1") {
            Write-Host "[ERROR] IP prohibida para el servidor." -ForegroundColor Red
            return $false
        }
        return $true
    }
    return $false
}

function Test-ValidarMask {
    param([string]$mask)
    return $mask -match "^(255|254|252|248|240|224|192|128|0)\.(255|254|252|248|240|224|192|128|0)\.(255|254|252|248|240|224|192|128|0)\.(255|254|252|248|240|224|192|128|0)$"
}

# --- 1. INSTALACIÓN ---
function Instalar-Servicios {
    Clear-Host
    Write-Host "[+] Instalando DHCP y DNS (Windows Features)..." -ForegroundColor Cyan
    Install-WindowsFeature -Name DHCP, DNS -IncludeManagementTools
    Set-Service -Name DHCPServer, DNS -StartupType Automatic
    Write-Host "[OK] Servicios instalados y habilitados." -ForegroundColor Green
    Read-Host "Enter para continuar..."
}

# --- 2. CONFIGURACIÓN DE RED / DHCP (Desplazamiento +1) ---
function Configurar-Sistema-Principal {
    Clear-Host
    Write-Host "--- CONFIGURACIÓN DE RED (RANGO DESPLAZADO +1) ---" -ForegroundColor Cyan

    # Detección de Interfaz
    $iface = (Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1).Name
    if (-not $iface) { $iface = "Ethernet 2" }

    while ($true) {
        $R_INI = Read-Host "Inicio de rango (ej. 10.10.10.0)"
        if (Test-ValidarIP $R_INI) { break }
    }
    while ($true) {
        $R_FIN = Read-Host "Fin de rango (ej. 10.10.10.10)"
        if (Test-ValidarIP $R_FIN) { break }
    }

    # Lógica de Segmento y Desplazamiento
    $global:IP_FIJA = $R_INI
    $parts = $R_INI.Split('.')
    $global:SEGMENTO = "$($parts[0]).$($parts[1]).$($parts[2])"
    [int]$OctIni = $parts[3]
    [int]$OctFin = $R_FIN.Split('.')[3]
    
    $DHCP_START = "$global:SEGMENTO.$($OctIni + 1)"
    $DHCP_END = "$global:SEGMENTO.$($OctFin + 1)"

    while ($true) {
        $MASK = Read-Host "Máscara [Enter para 255.255.255.0]"
        if ($MASK -eq "") { $MASK = "255.255.255.0"; break }
        if (Test-ValidarMask $MASK) { break }
    }

    $GW = Read-Host "Gateway [Enter para vacío]"
    $DNS_1 = Read-Host "DNS Primario [Opcional]"
    
    $LEASE_SEC = Read-Host "Lease time (segundos)"
    $LEASE = [TimeSpan]::FromSeconds([int]$LEASE_SEC)

    # Aplicar IP al Servidor
    Write-Host "[!] Aplicando IP Fija $global:IP_FIJA..." -ForegroundColor Yellow
    Remove-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias $iface -IPAddress $global:IP_FIJA -PrefixLength 24 -ErrorAction SilentlyContinue
    
    # FIX: Apuntar el servidor a sí mismo
    Set-DnsClientServerAddress -InterfaceAlias $iface -ServerAddresses ("127.0.0.1")

    # FIX DE INTERNET: Forwarders
    Add-DnsServerForwarder -IPAddress "8.8.8.8","8.8.4.4" -Force -ErrorAction SilentlyContinue

    # Configurar DHCP
    Remove-DhcpServerv4Scope -ScopeId "$global:SEGMENTO.0" -Force -ErrorAction SilentlyContinue
    Add-DhcpServerv4Scope -Name "Red_Examen" -StartRange $DHCP_START -EndRange $DHCP_END -SubnetMask $MASK -LeaseDuration $LEASE
    
    if ($GW -ne "") { Set-DhcpServerv4OptionValue -OptionId 3 -Value $GW }
    if ($DNS_1 -ne "") { Set-DhcpServerv4OptionValue -OptionId 6 -Value $DNS_1 }

    Restart-Service DHCPServer, DNS
    Write-Host "[!] LISTO. Server: $global:IP_FIJA | DHCP: $DHCP_START - $DHCP_END" -ForegroundColor Green
    Read-Host "Enter..."
}

# --- 3. DOMINIOS ---
function Add-Dominio {
    Clear-Host
    if ($global:IP_FIJA -eq "") { Write-Host "[!] Configure la red primero." -ForegroundColor Red; return }
    $DOM = Read-Host "Nombre del dominio (ej. jala.com)"
    if (Get-DnsServerZone -Name $DOM -ErrorAction SilentlyContinue) {
        Write-Host "[ERROR] El dominio ya existe." -ForegroundColor Red
    } else {
        Add-DnsServerPrimaryZone -Name $DOM -ZoneFile "$DOM.dns"
        Add-DnsServerResourceRecordA -Name "@" -IPv4Address $global:IP_FIJA -ZoneName $DOM
        Add-DnsServerResourceRecordA -Name "ns" -IPv4Address $global:IP_FIJA -ZoneName $DOM
        Write-Host "[OK] Dominio $DOM creado." -ForegroundColor Green
    }
    Read-Host "Enter..."
}

# --- 4. ELIMINAR ---
function Eliminar-Dominio {
    Clear-Host
    $DOM = Read-Host "Dominio a eliminar"
    if (Get-DnsServerZone -Name $DOM -ErrorAction SilentlyContinue) {
        Remove-DnsServerZone -Name $DOM -Force
        Write-Host "[OK] Dominio eliminado." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] El dominio no existe." -ForegroundColor Red
    }
    Read-Host "Enter..."
}

# --- 6. STATUS DETALLADO ---
function Check-Status {
    cls
    Write-Host "===============================================" -ForegroundColor Yellow
    Write-Host "          ESTADO GLOBAL DEL SISTEMA" -ForegroundColor Yellow
    Write-Host "===============================================" -ForegroundColor Yellow
    
    Write-Host "[1] SERVICIOS:"
    Get-Service DHCPServer, DNS | Select-Object Name, Status
    
    Write-Host "`n[2] RANGO DHCP (+1):"
    Get-DhcpServerv4Scope | Select-Object ScopeId, StartRange, EndRange
    
    Write-Host "`n[3] DOMINIOS DNS:"
    Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | Select-Object ZoneName
    
    Write-Host "`n[4] CONCESIONES RECIENTES:"
    Get-DhcpServerv4Lease -ScopeId "$global:SEGMENTO.0" -ErrorAction SilentlyContinue | Select-Object IPAddress, HostName
    
    Read-Host "`nPresione Enter..."
}

# --- MENÚ ---
while ($true) {
    cls
    Write-Host "==============================================="
    Write-Host "      SISTEMA DE ADMINISTRACIÓN DE RED"
    Write-Host "==============================================="
    Write-Host " IP ACTUAL SERVER: $global:IP_FIJA"
    Write-Host "-----------------------------------------------"
    Write-Host "1. Instalar DHCP/DNS"
    Write-Host "2. Configurar Rango / Red / DHCP (Desplazado +1)"
    Write-Host "3. Añadir Dominio DNS"
    Write-Host "4. Eliminar Dominio DNS"
    Write-Host "5. Listar Dominios"
    Write-Host "6. VER STATUS DETALLADO"
    Write-Host "7. Salir"
    Write-Host "-----------------------------------------------"
    $op = Read-Host "Opción"
    switch ($op) {
        "1" { Instalar-Servicios }
        "2" { Configurar-Sistema-Principal }
        "3" { Add-Dominio }
        "4" { Eliminar-Dominio }
        "5" { Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | Select-Object ZoneName; Read-Host "..." }
        "6" { Check-Status }
        "7" { exit }
    }
}