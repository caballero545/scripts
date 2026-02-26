# =====================================================================
# SCRIPT DE ADMINISTRACIÓN DE RED (DHCP/DNS) - WINDOWS SERVER EDITION
# =====================================================================

$global:IP_FIJA = ""
$global:INTERFACE = "Ethernet 2" # Asegúrate de que este sea el nombre de tu tarjeta
$global:SEGMENTO = ""

# --- FUNCIONES DE VALIDACIÓN ---

function Test-IsValidIP {
    param([string]$ip, [string]$tipo)
    if ($ip -eq "" -and ($tipo -eq "Opcional")) { return $true }
    if ($ip -match "^((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$") {
        # Prohibidas estrictas
        if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255" -or $ip -eq "127.0.0.1") {
            Write-Host "[ERROR] IP $ip prohibida por seguridad." -ForegroundColor Red
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
    Write-Host "Roles instalados. Configurando servicios..." -ForegroundColor Green
    Set-Service -Name DHCPServer -StartupType Automatic
    Set-Service -Name DNS -StartupType Automatic
    Read-Host "Presione Enter para continuar..."
}

# --- 2. CONFIGURACIÓN DE RED Y DHCP (Lógica Desplazada +1) ---
function Configurar-RedPrincipal {
    Clear-Host
    Write-Host "--- CONFIGURACIÓN DE RANGO Y RED ---" -ForegroundColor Cyan

    # Rango Inicial
    while ($true) {
        $R_INI = Read-Host "Ingrese inicio de rango (ej. 192.168.100.20)"
        if (Test-IsValidIP $R_INI "Requerido") { break }
    }

    # Rango Final
    while ($true) {
        $R_FIN = Read-Host "Ingrese fin de rango (ej. 192.168.100.30)"
        if (Test-IsValidIP $R_FIN "Requerido") { break }
    }

    # LÓGICA SOLICITADA: IP Fija es la primera del rango
    $global:IP_FIJA = $R_INI
    $Octetos = $R_INI.Split('.')
    $global:SEGMENTO = "$($Octetos[0]).$($Octetos[1]).$($Octetos[2])"
    
    # Lógica de desplazamiento +1 para el DHCP
    $OctIni = [int]$R_INI.Split('.')[3]
    $OctFin = [int]$R_FIN.Split('.')[3]
    $DHCP_START = "$global:SEGMENTO.$($OctIni + 1)"
    $DHCP_END = "$global:SEGMENTO.$($OctFin + 1)"

    # Máscara
    while ($true) {
        $MASK = Read-Host "Máscara de red [Enter para 255.255.255.0]"
        if ($MASK -eq "") { $MASK = "255.255.255.0"; break }
        if (Test-IsValidMask $MASK) { break }
    }

    $GW = Read-Host "Puerta de enlace (Gateway) [Enter para vacío]"
    
    while ($true) {
        $DNS_1 = Read-Host "DNS Primario [Enter para vacío]"
        if (Test-IsValidIP $DNS_1 "Opcional") { break }
    }

    while ($true) {
        $DNS_2 = Read-Host "DNS Secundario (OPCIONAL) [Enter para vacío]"
        if (Test-IsValidIP $DNS_2 "Opcional") { break }
    }

    while ($true) {
        $LEASE_STR = Read-Host "Tiempo de concesión (segundos)"
        if ($LEASE_STR -match "^\d+$") { 
            $LEASE = [TimeSpan]::FromSeconds([int]$LEASE_STR)
            break 
        }
    }

    # --- APLICAR CAMBIOS EN WINDOWS ---
    Write-Host "[!] Aplicando IP Fija: $global:IP_FIJA..." -ForegroundColor Yellow
    New-NetIPAddress -InterfaceAlias $global:INTERFACE -IPAddress $global:IP_FIJA -PrefixLength 24 -ErrorAction SilentlyContinue
    
    # Configurar DNS del propio adaptador (Loopback para que el DNS resuelva)
    Set-DnsClientServerAddress -InterfaceAlias $global:INTERFACE -ServerAddresses ("127.0.0.1")

    # Configurar DHCP Scope
    Remove-DhcpServerv4Scope -ScopeId "$global:SEGMENTO.0" -Force -ErrorAction SilentlyContinue
    Add-DhcpServerv4Scope -Name "Rango_Dinamico" -StartRange $DHCP_START -EndRange $DHCP_END -SubnetMask $MASK -LeaseDuration $LEASE
    
    if ($GW -ne "") { Set-DhcpServerv4OptionValue -OptionId 3 -Value $GW }
    
    # Configurar DNS en DHCP
    $DNS_List = @()
    if ($DNS_1 -ne "") { $DNS_List += $DNS_1 }
    if ($DNS_2 -ne "") { $DNS_List += $DNS_2 }
    if ($DNS_List.Count -gt 0) { Set-DhcpServerv4OptionValue -OptionId 6 -Value $DNS_List }

    Restart-Service DHCPServer, DNS
    Write-Host "`n[OK] SISTEMA CONFIGURADO:" -ForegroundColor Green
    Write-Host "    - IP Servidor: $global:IP_FIJA"
    Write-Host "    - Rango DHCP (+1): $DHCP_START - $DHCP_END"
    Read-Host "Presione Enter..."
}

# --- 3. GESTIÓN DE DOMINIOS ---
function Add-Dominio {
    Clear-Host
    if ($global:IP_FIJA -eq "") { Write-Host "Error: Configure la red primero." -ForegroundColor Red; return }
    
    $DOM = Read-Host "Nombre del dominio (ej. reprobo.com)"
    if ($DOM -match "^[a-zA-Z0-9][-a-zA-Z0-9.]*\.[a-zA-Z]{2,}$") {
        if (Get-DnsServerZone -Name $DOM -ErrorAction SilentlyContinue) {
            Write-Host "ERROR: El dominio ya existe." -ForegroundColor Red
        } else {
            Add-DnsServerPrimaryZone -Name $DOM -ZoneFile "$DOM.dns"
            Add-DnsServerResourceRecordA -Name "@" -IPv4Address $global:IP_FIJA -ZoneName $DOM
            Add-DnsServerResourceRecordA -Name "ns" -IPv4Address $global:IP_FIJA -ZoneName $DOM
            Write-Host "Dominio $DOM creado exitosamente." -ForegroundColor Green
        }
    } else {
        Write-Host "Nombre de dominio no válido." -ForegroundColor Red
    }
    Read-Host "Enter..."
}

function Eliminar-Dominio {
    Clear-Host
    $DOM = Read-Host "Dominio a eliminar"
    if (Get-DnsServerZone -Name $DOM -ErrorAction SilentlyContinue) {
        Remove-DnsServerZone -Name $DOM -Force
        Write-Host "Dominio eliminado." -ForegroundColor Green
    } else {
        Write-Host "El dominio no existe." -ForegroundColor Red
    }
    Read-Host "Enter..."
}

# --- 4. STATUS ---
function Check-Status {
    cls
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host "      ESTADO DEL SISTEMA (WINDOWS PRO)" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Yellow
    
    $dhcp = Get-Service DHCPServer
    $dns = Get-Service DNS
    
    Write-Host "Servicio DHCP: " -NoNewline; Write-Host $dhcp.Status -ForegroundColor ($((if($dhcp.Status -eq 'Running') {'Green'} else {'Red'})))
    Write-Host "Servicio DNS:  " -NoNewline; Write-Host $dns.Status -ForegroundColor ($((if($dns.Status -eq 'Running') {'Green'} else {'Red'})))
    
    Write-Host "`nIP Actual: $global:IP_FIJA"
    Write-Host "`nDominios Activos:"
    Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | Select-Object ZoneName
    
    Write-Host "`nÚltimas concesiones DHCP:"
    Get-DhcpServerv4Lease -ScopeId "$global:SEGMENTO.0" -ErrorAction SilentlyContinue | Select-Object IPAddress, ClientId, HostName
    
    Read-Host "`nPresione Enter..."
}

# --- MENÚ PRINCIPAL ---
while ($true) {
    cls
    Write-Host "--- ADMINISTRADOR DE RED WINDOWS ---" -ForegroundColor Cyan
    Write-Host "IP SERVER: $global:IP_FIJA" -ForegroundColor Gray
    Write-Host "1. Instalar Roles"
    Write-Host "2. Configurar Red / Rango DHCP (Lógica +1)"
    Write-Host "3. Añadir Dominio DNS"
    Write-Host "4. Eliminar Dominio DNS"
    Write-Host "5. Listar Dominios"
    Write-Host "6. Status Detallado"
    Write-Host "7. Salir"
    
    $op = Read-Host "Opción"
    switch ($op) {
        "1" { Instalar-Servicios }
        "2" { Configurar-RedPrincipal }
        "3" { Add-Dominio }
        "4" { Eliminar-Dominio }
        "5" { Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | Select-Object ZoneName; Read-Host "Enter..." }
        "6" { Check-Status }
        "7" { exit }
    }
}