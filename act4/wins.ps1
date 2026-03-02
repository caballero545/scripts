# --- 1. INSTALACIÓN DE ROLES ---
function Instalar-Servicios {
    Write-Host "--- Instalando Roles DNS y DHCP ---" -ForegroundColor Cyan
    Install-WindowsFeature -Name DNS, DHCP -IncludeManagementTools
    Write-Host "Servicios instalados correctamente." -ForegroundColor Green
    Read-Host "Presiona Enter para continuar..."
}

# --- 2. IP FIJA ---
function Establecer-IPFija-Logic {
    $interface = "Ethernet" # Ajustar según el nombre en tu Windows
    $ipIng = Read-Host "Ingrese IP Fija (ej. 77.77.77.7)"
    
    if ($ipIng -match "^\d{1,3}(\.\d{1,3}){3}$") {
        # Configurar IP Fija en Windows
        New-NetIPAddress -InterfaceAlias $interface -IPAddress $ipIng -PrefixLength 24 -DefaultGateway "$($ipIng.Substring(0,$ipIng.LastIndexOf('.'))).1" -Confirm:$false
        Set-DnsClientServerAddress -InterfaceAlias $interface -ServerAddresses ("127.0.0.1")
        
        Write-Host "IP $ipIng establecida." -ForegroundColor Green
        return $ipIng
    } else {
        return "ERROR"
    }
}

# --- 3. DHCP ---
function Config-DHCP-Logic {
    param($ipFija, $segmento, $octSrv)
    
    $gw = "$segmento.1"
    $ipIni = Read-Host "IP Inicial (Mínimo $segmento.$($octSrv + 1))"
    $ipFin = Read-Host "IP Final"
    $lease = Read-Host "Lease Time (ej. 08:00:00)"

    # Autorizar Servidor DHCP en AD (Si no hay AD, se omite o usa comando local)
    Add-DhcpServerv4Scope -Name "Scope_Principal" -StartRange $ipIni -EndRange $ipFin -SubnetMask 255.255.255.0
    Set-DhcpServerv4OptionValue -OptionId 3 -Value $gw # Gateway
    Set-DhcpServerv4OptionValue -OptionId 6 -Value $ipFija # DNS Server
    
    Write-Host "DHCP configurado en Windows Server." -ForegroundColor Green
    Read-Host "Enter..."
}

# --- 4. DOMINIOS ---
function Add-Dominio-Logic {
    param($dom, $ipFija)
    
    # Verificar si existe la zona
    if (Get-DnsServerZone -Name $dom -ErrorAction SilentlyContinue) {
        return 1 # Ya existe
    }

    # Crear zona primaria y registro A
    Add-DnsServerPrimaryZone -Name $dom -ZoneFile "$dom.dns"
    Add-DnsServerResourceRecordA -Name "@" -IPv4Address $ipFija -ZoneName $dom
    Add-DnsServerResourceRecordA -Name "ns" -IPv4Address $ipFija -ZoneName $dom
    
    return 0
}

function Del-Dominio-Logic {
    param($dom)
    if (!(Get-DnsServerZone -Name $dom -ErrorAction SilentlyContinue)) {
        return 1 # No existe
    }
    Remove-DnsServerZone -Name $dom -Force
    return 0
}

# --- 7. STATUS ---
function Check-Status-Logic {
    param($ipActual)
    Clear-Host
    Write-Host "====== ESTADO DEL SISTEMA (WINDOWS) ======" -ForegroundColor Cyan
    
    $dhcpStatus = Get-Service -Name DHCPServer
    $dnsStatus = Get-Service -Name DNS
    
    Write-Host "Servicio DHCP: " -NoNewline; Write-Host $dhcpStatus.Status -ForegroundColor ($($dhcpStatus.Status -eq 'Running' ? 'Green' : 'Red'))
    Write-Host "Servicio DNS:  " -NoNewline; Write-Host $dnsStatus.Status -ForegroundColor ($($dnsStatus.Status -eq 'Running' ? 'Green' : 'Red'))

    Write-Host "`n--- Dominios Activos ---"
    Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | Select-Object ZoneName, ZoneType
    
    Write-Host "`n--- Configuración de Red ---"
    Get-NetIPAddress -InterfaceAlias "Ethernet*" -AddressFamily IPv4 | Select-Object IPAddress, InterfaceAlias
    
    Read-Host "`nPresiona Enter para volver..."
}