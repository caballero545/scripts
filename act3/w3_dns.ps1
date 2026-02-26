# =====================================================================
# SCRIPT DE ADMINISTRACIÓN DE RED (WINDOWS SERVER - VERSION PRO)
# MIGRACIÓN LÍNEA POR LÍNEA DESDE LINUX
# =====================================================================

$global:IP_FIJA = ""
$global:SEGMENTO = ""

# --- FUNCIONES DE VALIDACIÓN ---

function Test-ValidarIP {
    param([string]$ip)
    # Regex para validar formato IP
    if ($ip -match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$") {
        # IPs prohibidas (Réplica de Linux)
        if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255" -or $ip -eq "127.0.0.1" -or $ip -eq "127.0.0.0") {
            Write-Host "[ERROR] IP prohibida para el servidor." -ForegroundColor Red
            return $false
        }
        return $true
    }
    return $false
}

function Test-ValidarIP-DNS {
    param([string]$ip)
    if ($ip -eq "") { return $true }
    if ($ip -match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$") {
        if ($ip -eq "255.255.255.255" -or $ip -eq "1.0.0.0") {
            Write-Host "[ERROR] IP prohibida para DNS." -ForegroundColor Red
            return $false
        }
        return $true
    }
    return $false
}

# --- 1. INSTALACIÓN ---
function Instalar-Servicios {
    Clear-Host
    Write-Host "`n[+] Instalando DHCP y DNS..." -ForegroundColor Cyan
    Install-WindowsFeature -Name DHCP, DNS -IncludeManagementTools
    Set-Service -Name DHCPServer, DNS -StartupType Automatic
    Write-Host "Servicios instalados. Enter..." -ForegroundColor Green
    Read-Host
}

# --- 2. CONFIGURACIÓN DE RED / DHCP (Desplazamiento +1) ---
function Configurar-Sistema-Principal {
    Clear-Host
    Write-Host "--- CONFIGURACIÓN DE RED (RANGO DESPLAZADO +1) ---" -ForegroundColor Cyan

    # Auto-detección de interfaz
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

    # Lógica de Segmento y Octetos (Réplica de cut -d'.')
    $global:IP_FIJA = $R_INI
    $parts = $R_INI.Split('.')
    $global:SEGMENTO = "$($parts[0]).$($parts[1]).$($parts[2])"
    [int]$OctIni = $parts[3]
    [int]$OctFin = $R_FIN.Split('.')[3]
    
    $DHCP_START = "$global:SEGMENTO.$($OctIni + 1)"
    $DHCP_END = "$global:SEGMENTO.$($OctFin + 1)"

    $MASK = Read-Host "Máscara [Enter para 255.255.255.0]"
    if ($MASK -eq "") { $MASK = "255.255.255.0" }

    $GW = Read-Host "Gateway [Enter para vacío]"

    while ($true) {
        $DNS_1 = Read-Host "DNS Primario [Opcional]"
        if (Test-ValidarIP-DNS $DNS_1) { break }
    }

    $LEASE_SEC = Read-Host "Lease time (segundos)"
    if ($LEASE_SEC -match "^\d+$") { $LEASE = [TimeSpan]::FromSeconds([int]$LEASE_SEC) } else { $LEASE = [TimeSpan]::FromHours(8) }

    # Aplicar IP a la interfaz (Réplica de ip addr flush/add)
    Write-Host "[!] Aplicando IP $global:IP_FIJA..." -ForegroundColor Yellow
    Remove-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias $iface -IPAddress $global:IP_FIJA -PrefixLength 24 -ErrorAction SilentlyContinue
    
    # FIX DEL PING: Apuntar el servidor a sí mismo
    Set-DnsClientServerAddress -InterfaceAlias $iface -ServerAddresses ("127.0.0.1")

    # FIX DE INTERNET: Forwarders (Réplica de named.conf.options)
    Add-DnsServerForwarder -IPAddress "8.8.8.8","8.8.4.4" -Force -ErrorAction SilentlyContinue

    # Configurar DHCP (Réplica de dhcpd.conf)
    $scopeId = "$global:SEGMENTO.0"
    Remove-DhcpServerv4Scope -ScopeId $scopeId -Force -ErrorAction SilentlyContinue
    Add-DhcpServerv4Scope -Name "Red_Examen" -StartRange $DHCP_START -EndRange $DHCP_END -SubnetMask $MASK -LeaseDuration $LEASE
    
    if ($GW -ne "") { Set-DhcpServerv4OptionValue -OptionId 3 -Value $GW }
    if ($DNS_1 -ne "") { Set-DhcpServerv4OptionValue -OptionId 6 -Value $DNS_1 }

    Restart-Service DHCPServer, DNS
    Write-Host "`n[!] LISTO. IP Server: $global:IP_FIJA | Rango DHCP: $DHCP_START - $DHCP_END" -ForegroundColor Green
    Read-Host "Enter..."
}

# --- 3. DOMINIOS ---
function Add-Dominio {
    Clear-Host
    if ($global:IP_FIJA -eq "") { Write-Host "[!] Configure la red primero (Opción 2)." -ForegroundColor Red; return }
    
    $DOM = Read-Host "Nombre del dominio (ej. jala.com)"
    if ($DOM -eq "") { return }

    if (Get-DnsServerZone -Name $DOM -ErrorAction SilentlyContinue) {
        Write-Host "[ERROR] El dominio ya existe." -ForegroundColor Red
    } else {
        Add-DnsServerPrimaryZone -Name $DOM -ZoneFile "$DOM.dns"
        Add-DnsServerResourceRecordA -Name "@" -IPv4Address $global:IP_FIJA -ZoneName $DOM
        Add-DnsServerResourceRecordA -Name "ns" -IPv4Address $global:IP_FIJA -ZoneName $DOM
        Write-Host "[OK] Dominio '$DOM' creado exitosamente." -ForegroundColor Green
    }
    Read-Host "Enter..."
}

# --- 4. ELIMINAR ---
function Eliminar-Dominio {
    Clear-Host
    $DOM = Read-Host "Ingrese el nombre del dominio a eliminar"
    if (Get-DnsServerZone -Name $DOM -ErrorAction SilentlyContinue) {
        Remove-DnsServerZone -Name $DOM -Force
        Write-Host "[OK] Dominio '$DOM' eliminado correctamente." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] El dominio no existe." -ForegroundColor Red
    }
    Read-Host "Enter..."
}

# --- 6. CHECK STATUS ---
function Check-Status {
    cls
    Write-Host "==============================================="
    Write-Host "          ESTADO GLOBAL DEL SISTEMA" -ForegroundColor Yellow
    Write-Host "==============================================="
    
    Write-Host "`n[1] SERVICIOS:"
    Get-Service DHCPServer, DNS | Select-Object Name, Status
    
    Write-Host "`n[2] RANGO DHCP (+1):"
    Get-DhcpServerv4Scope | Select-Object ScopeId, StartRange, EndRange
    
    Write-Host "`n[3] DOMINIOS ACTIVOS:"
    Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | Select-Object ZoneName
    
    Read-Host "`nPresione Enter para volver..."
}

# --- MENÚ ---
while ($true) {
    cls
    Write-Host "==============================================="
    Write-Host "      SISTEMA DE ADMINISTRACIÓN DE RED" -ForegroundColor Cyan
    Write-Host "==============================================="
    $statusIp = if($global:IP_FIJA -eq "") { "PENDIENTE" } else { $global:IP_FIJA }
    Write-Host " IP ACTUAL SERVER: $statusIp"
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