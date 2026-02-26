# =====================================================================
# SCRIPT DE ADMINISTRACION DE RED (WINDOWS SERVER) - VERSION FINAL
# =====================================================================

$global:IP_FIJA = ""
$global:SEGMENTO = ""

# --- FUNCIONES DE VALIDACION ---
function Test-ValidarIP {
    param([string]$ip)
    if ($ip -match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$") {
        if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255" -or $ip -eq "127.0.0.1") {
            Write-Host "Error: IP prohibida." -ForegroundColor Red
            return $false
        }
        return $true
    }
    return $false
}

# --- 1. INSTALACION ---
function Instalar-Servicios {
    Clear-Host
    Write-Host "Instalando DHCP y DNS..." -ForegroundColor Cyan
    Install-WindowsFeature -Name DHCP, DNS -IncludeManagementTools
    Set-Service -Name DHCPServer, DNS -StartupType Automatic
    Write-Host "Instalado. Presione Enter para continuar..." -ForegroundColor Green
    Read-Host
}

# --- 2. CONFIGURACION DE RED / DHCP (Logica +1) ---
function Configurar-Principal {
    Clear-Host
    Write-Host "CONFIGURACION DE RED Y DHCP (Logica +1)" -ForegroundColor Cyan

    # Deteccion de interfaz
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

    # Procesamiento Matematico
    $global:IP_FIJA = $R_INI
    $parts = $R_INI.Split('.')
    $global:SEGMENTO = "$($parts[0]).$($parts[1]).$($parts[2])"
    [int]$OctIni = $parts[3]
    [int]$OctFin = $R_FIN.Split('.')[3]
    
    $DHCP_START = "$global:SEGMENTO.$($OctIni + 1)"
    $DHCP_END = "$global:SEGMENTO.$($OctFin + 1)"

    $MASK = Read-Host "Mascara (Enter para 255.255.255.0)"
    if ($MASK -eq "") { $MASK = "255.255.255.0" }
    
    $GW = Read-Host "Gateway (Enter para vacio)"
    $DNS_EXT = Read-Host "DNS Externo (Opcional)"
    
    $LEASE_SEC = Read-Host "Lease time en segundos"
    if ($LEASE_SEC -match "^\d+$") { $L_TIME = [TimeSpan]::FromSeconds([int]$LEASE_SEC) } else { $L_TIME = [TimeSpan]::FromHours(8) }

    # Aplicar Red
    Write-Host "Aplicando IP fija..." -ForegroundColor Yellow
    Remove-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias $iface -IPAddress $global:IP_FIJA -PrefixLength 24 -ErrorAction SilentlyContinue
    
    # DNS Local y Forwarder
    Set-DnsClientServerAddress -InterfaceAlias $iface -ServerAddresses ("127.0.0.1")
    Add-DnsServerForwarder -IPAddress "8.8.8.8" -Force -ErrorAction SilentlyContinue

    # Configurar DHCP
    $scopeId = "$global:SEGMENTO.0"
    Remove-DhcpServerv4Scope -ScopeId $scopeId -Force -ErrorAction SilentlyContinue
    Add-DhcpServerv4Scope -Name "RedExamen" -StartRange $DHCP_START -EndRange $DHCP_END -SubnetMask $MASK -LeaseDuration $L_TIME
    
    if ($GW -ne "") { Set-DhcpServerv4OptionValue -OptionId 3 -Value $GW }
    if ($DNS_EXT -ne "") { Set-DhcpServerv4OptionValue -OptionId 6 -Value $DNS_EXT }

    Restart-Service DHCPServer, DNS
    Write-Host "Listo. Servidor: $global:IP_FIJA | DHCP: $DHCP_START - $DHCP_END" -ForegroundColor Green
    Read-Host "Enter..."
}

# --- 3. DOMINIOS ---
function Add-Dominio {
    Clear-Host
    if ($global:IP_FIJA -eq "") { Write-Host "Configure red primero." -ForegroundColor Red; return }
    $DOM = Read-Host "Nombre del dominio"
    if ($DOM -eq "") { return }
    if (Get-DnsServerZone -Name $DOM -ErrorAction SilentlyContinue) {
        Write-Host "Ese dominio ya existe." -ForegroundColor Red
    } else {
        Add-DnsServerPrimaryZone -Name $DOM -ZoneFile "$DOM.dns"
        Add-DnsServerResourceRecordA -Name "@" -IPv4Address $global:IP_FIJA -ZoneName $DOM
        Add-DnsServerResourceRecordA -Name "ns" -IPv4Address $global:IP_FIJA -ZoneName $DOM
        Write-Host "Dominio creado con exito." -ForegroundColor Green
    }
    Read-Host "Enter para continuar..."
}

# --- 4. ELIMINAR ---
function Eliminar-Dominio {
    Clear-Host
    $DOM = Read-Host "Dominio a eliminar"
    if (Get-DnsServerZone -Name $DOM -ErrorAction SilentlyContinue) {
        Remove-DnsServerZone -Name $DOM -Force
        Write-Host "Dominio eliminado correctamente." -ForegroundColor Green
    } else {
        Write-Host "El dominio no existe." -ForegroundColor Red
    }
    Read-Host "Enter..."
}

# --- 6. STATUS ---
function Check-Status {
    cls
    Write-Host "ESTADO DEL SISTEMA" -ForegroundColor Yellow
    Write-Host "1. SERVICIOS:"
    Get-Service DHCPServer, DNS | Select-Object Name, Status
    Write-Host "2. RANGO DHCP:"
    Get-DhcpServerv4Scope | Select-Object ScopeId, StartRange, EndRange
    Write-Host "3. DOMINIOS:"
    Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | Select-Object ZoneName
    Read-Host "Presione Enter para volver..."
}

# --- MENU ---
while ($true) {
    cls
    Write-Host "===================================="
    Write-Host "   ADMINISTRADOR DE RED WINDOWS"
    Write-Host "===================================="
    $ipActual = if($global:IP_FIJA -eq "") { "PENDIENTE" } else { $global:IP_FIJA }
    Write-Host " IP SERVER: $ipActual"
    Write-Host "------------------------------------"
    Write-Host "1. Instalar DHCP y DNS"
    Write-Host "2. Configurar Red y DHCP (+1)"
    Write-Host "3. Añadir Dominio DNS"
    Write-Host "4. Eliminar Dominio DNS"
    Write-Host "5. Listar Dominios"
    Write-Host "6. Ver Status detallado"
    Write-Host "7. Salir"
    Write-Host "------------------------------------"
    
    $op = Read-Host "Seleccione opcion"
    switch ($op) {
        "1" { Instalar-Servicios }
        "2" { Configurar-Principal }
        "3" { Add-Dominio }
        "4" { Eliminar-Dominio }
        "5" { Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | Select-Object ZoneName; Read-Host "Presione Enter..." }
        "6" { Check-Status }
        "7" { exit }
    }
}