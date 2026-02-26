# =====================================================================
# SCRIPT DE ADMINISTRACIÓN DE RED (DHCP/DNS) - WINDOWS SERVER FINAL
# =====================================================================

$global:IP_FIJA = ""
$global:SEGMENTO = ""

# --- FUNCIONES DE VALIDACIÓN ---

function Test-IsValidIP {
    param([string]$ip)
    # Valida que sea un formato IP correcto y no sea una reservada problemática
    if ($ip -match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$") {
        if ($ip -eq "0.0.0.0" -or $ip -eq "127.0.0.1") { return $false }
        return $true
    }
    return $false
}

# --- 1. INSTALACIÓN DE ROLES ---
function Instalar-Servicios {
    Clear-Host
    Write-Host "[+] Instalando Roles DHCP y DNS..." -ForegroundColor Cyan
    Install-WindowsFeature -Name DHCP, DNS -IncludeManagementTools
    Write-Host "Configurando servicios en inicio automático..." -ForegroundColor Green
    Set-Service -Name DHCPServer -StartupType Automatic
    Set-Service -Name DNS -StartupType Automatic
    Read-Host "Presione Enter para continuar..."
}

# --- 2. CONFIGURACIÓN DE RED Y DHCP (Lógica Desplazada +1) ---
function Configurar-RedPrincipal {
    Clear-Host
    Write-Host "--- CONFIGURACIÓN DE RED Y RANGO DHCP ---" -ForegroundColor Cyan

    # Auto-detección de interfaz activa para evitar errores de nombre
    $iface = (Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1).Name
    if (-not $iface) { $iface = "Ethernet 2" }
    Write-Host "[i] Usando interfaz detectada: $iface" -ForegroundColor Gray

    # Rango Inicial
    while ($true) {
        $R_INI = Read-Host "Ingrese inicio de rango (ej. 10.10.10.10)"
        if (Test-IsValidIP $R_INI) { break }
        Write-Host "IP no válida." -ForegroundColor Red
    }

    # Rango Final
    while ($true) {
        $R_FIN = Read-Host "Ingrese fin de rango (ej. 10.10.10.20)"
        if (Test-IsValidIP $R_FIN) { break }
        Write-Host "IP no válida." -ForegroundColor Red
    }

    # --- LÓGICA DE PROCESAMIENTO ---
    $global:IP_FIJA = $R_INI
    $parts = $R_INI.Split('.')
    $global:SEGMENTO = "$($parts[0]).$($parts[1]).$($parts[2])"
    
    # Casting a [int] para evitar el error de concatenación de texto
    [int]$OctIni = $parts[3]
    [int]$OctFin = $R_FIN.Split('.')[3]
    
    # Desplazamiento +1 para el DHCP
    $DHCP_START = "$global:SEGMENTO.$($OctIni + 1)"
    $DHCP_END = "$global:SEGMENTO.$($OctFin + 1)"

    # --- APLICAR CAMBIOS ---
    Write-Host "[!] Aplicando IP Fija $global:IP_FIJA al servidor..." -ForegroundColor Yellow
    # Limpiamos IPs previas para evitar conflictos
    Remove-NetIPAddress -InterfaceAlias $iface -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias $iface -IPAddress $global:IP_FIJA -PrefixLength 24 -ErrorAction SilentlyContinue
    
    # Configurar DNS del adaptador para que el servidor se consulte a sí mismo
    Set-DnsClientServerAddress -InterfaceAlias $iface -ServerAddresses ("127.0.0.1")

    # SOLUCIÓN INTERNET: Reenviadores DNS
    # Esto permite que el servidor resuelva dominios externos (google.com)
    Add-DnsServerForwarder -IPAddress "8.8.8.8" -Force -ErrorAction SilentlyContinue

    # --- CONFIGURAR DHCP ---
    # Borramos scope anterior si existe
    Remove-DhcpServerv4Scope -ScopeId "$global:SEGMENTO.0" -Force -ErrorAction SilentlyContinue
    Add-DhcpServerv4Scope -Name "Red_Examen" -StartRange $DHCP_START -EndRange $DHCP_END -SubnetMask "255.255.255.0" -LeaseDuration (New-TimeSpan -Hours 8)
    
    # Opción 6: Decirle a los clientes que el servidor DNS es ESTE servidor
    Set-DhcpServerv4OptionValue -OptionId 6 -Value $global:IP_FIJA

    Restart-Service DHCPServer, DNS
    Write-Host "`n[OK] SISTEMA CONFIGURADO:" -ForegroundColor Green
    Write-Host "    - IP Servidor: $global:IP_FIJA"
    Write-Host "    - DHCP (+1): $DHCP_START - $DHCP_END"
    Read-Host "Presione Enter..."
}

# --- 3. GESTIÓN DE DOMINIOS (CON VALIDACIÓN DE DUPLICADOS) ---
function Add-Dominio {
    Clear-Host
    if ($global:IP_FIJA -eq "") { Write-Host "Error: Configure la red primero (Opción 2)." -ForegroundColor Red; return }
    
    $DOM = Read-Host "Nombre del nuevo dominio (ej. jala.com)"
    
    # Validar si ya existe
    if (Get-DnsServerZone -Name $DOM -ErrorAction SilentlyContinue) {
        Write-Host "[ERROR] El dominio '$DOM' ya existe en este servidor." -ForegroundColor Red
    } else {
        Add-DnsServerPrimaryZone -Name $DOM -ZoneFile "$DOM.dns"
        Add-DnsServerResourceRecordA -Name "@" -IPv4Address $global:IP_FIJA -ZoneName $DOM
        Add-DnsServerResourceRecordA -Name "ns" -IPv4Address $global:IP_FIJA -ZoneName $DOM
        Write-Host "[OK] Dominio $DOM creado exitosamente." -ForegroundColor Green
    }
    Read-Host "Enter..."
}

function Eliminar-Dominio {
    Clear-Host
    $DOM = Read-Host "Nombre del dominio a eliminar"
    if (Get-DnsServerZone -Name $DOM -ErrorAction SilentlyContinue) {
        Remove-DnsServerZone -Name $DOM -Force
        Write-Host "[OK] Dominio eliminado." -ForegroundColor Green
    } else {
        Write-Host "[ERROR] El dominio no existe." -ForegroundColor Red
    }
    Read-Host "Enter..."
}

# --- 4. STATUS ---
function Check-Status {
    cls
    Write-Host "=== ESTADO DE SERVICIOS ===" -ForegroundColor Yellow
    Get-Service DHCPServer, DNS | Select-Object Name, Status
    Write-Host "`n=== RANGO DHCP ACTUAL ===" -ForegroundColor Yellow
    Get-DhcpServerv4Scope | Select-Object ScopeId, StartRange, EndRange
    Write-Host "`n=== ZONAS DNS ACTIVAS ===" -ForegroundColor Yellow
    Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | Select-Object ZoneName
    Read-Host "`nPresione Enter..."
}

# --- MENÚ PRINCIPAL ---
while ($true) {
    cls
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "      ADMINISTRADOR DE RED WINDOWS SERVER" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host " IP ACTUAL: $global:IP_FIJA" -ForegroundColor Gray
    Write-Host " 1. Instalar Roles"
    Write-Host " 2. Configurar Red / DHCP (Lógica +1)"
    Write-Host " 3. Añadir Dominio DNS"
    Write-Host " 4. Eliminar Dominio DNS"
    Write-Host " 5. Ver Status Detallado"
    Write-Host " 6. Salir"
    
    $op = Read-Host "Opción"
    switch ($op) {
        "1" { Instalar-Servicios }
        "2" { Configurar-RedPrincipal }
        "3" { Add-Dominio }
        "4" { Eliminar-Dominio }
        "5" { Check-Status }
        "6" { exit }
    }
}