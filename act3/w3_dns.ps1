# --- CONFIGURACION INICIAL ---
$IP_FIJA = ""
$INTERFACE = "Ethernet" 

function Limpiar-ZonasBasura {
    # En Windows, las zonas vacias no se crean por error de 'Enter' 
    # pero esto asegura que el servicio este limpio.
    Write-Host "Limpiando configuracion DNS..." -ForegroundColor Gray
}

function Instalar-Servicios {
    Write-Host "--- Instalando DHCP y DNS ---" -ForegroundColor Cyan
    Install-WindowsFeature -Name DHCP, DNS -IncludeManagementTools
    Write-Host "Servicios instalados."
    Read-Host "Presione Enter para volver"
}

function Establecer-IPFija {
    Write-Host "--- Configurar IP Fija y Activar DNS ---" -ForegroundColor Cyan
    $IP_ING = Read-Host "Ingrese la IP Fija (ej. 11.11.11.2)"
    if ($IP_ING -match "^\d{1,3}(\.\d{1,3}){3}$") {
        $global:IP_FIJA = $IP_ING
        $Octetos = $IP_FIJA.Split('.')
        $global:SEGMENTO = "$($Octetos[0]).$($Octetos[1]).$($Octetos[2])"
        $global:OCT_SRV = [int]$Octetos[3]
        
        # Aplicar IP y activar DNS
        New-NetIPAddress -InterfaceAlias $INTERFACE -IPAddress $IP_FIJA -PrefixLength 24 -DefaultGateway "$SEGMENTO.1" -ErrorAction SilentlyContinue
        Restart-Service DNS
        Write-Host "IP $IP_FIJA fijada y DNS reiniciado." -ForegroundColor Green
    } else {
        Write-Host "IP invalida." -ForegroundColor Red
    }
    Read-Host "Enter..."
}

function Configurar-DHCP {
    if ($global:IP_FIJA -eq "") { Write-Host "Error: Ponga IP Fija primero." -ForegroundColor Red; return }
    $MIN_INI = $global:OCT_SRV + 1
    $IP_INI = Read-Host "IP Inicial (Minimo $SEGMENTO.$MIN_INI)"
    $IP_FIN = Read-Host "IP Final"
    
    Add-DhcpServerv4Scope -Name "RangoDHCP" -StartRange $IP_INI -EndRange $IP_FIN -SubnetMask 255.255.255.0 -State Active
    Set-DhcpServerv4OptionValue -OptionId 3 -Value "$SEGMENTO.1" # Gateway .1
    Set-DhcpServerv4OptionValue -OptionId 6 -Value $IP_FIJA       # DNS es el Server
    
    Restart-Service DHCPServer
    Write-Host "DHCP Activo." -ForegroundColor Green
    Read-Host "Enter..."
}

function Add-Dominio {
    $DOM = Read-Host "Nombre del dominio (ej. aprobado.com)"
    Add-DnsServerPrimaryZone -Name $DOM -ReplicationScope "None" -ErrorAction SilentlyContinue
    Add-DnsServerResourceRecordA -Name "@" -IPv4Address $IP_FIJA -ZoneName $DOM
    Add-DnsServerResourceRecordA -Name "ns" -IPv4Address $IP_FIJA -ZoneName $DOM
    Write-Host "Dominio $DOM creado apuntando a $IP_FIJA." -ForegroundColor Green
    Read-Host "Enter..."
}

function Del-Dominio {
    $DOM_DEL = Read-Host "Nombre EXACTO del dominio a borrar"
    if (Get-DnsServerZone -Name $DOM_DEL -ErrorAction SilentlyContinue) {
        Remove-DnsServerZone -Name $DOM_DEL -Force
        Write-Host "Dominio $DOM_DEL eliminado de forma segura." -ForegroundColor Green
    } else {
        Write-Host "El dominio no existe." -ForegroundColor Red
    }
    Read-Host "Enter..."
}

function Listar-Dominios {
    Write-Host "--- Dominios en el Servidor ---" -ForegroundColor Yellow
    Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false -and $_.ZoneName -ne "TrustAnchors" } | Select-Object ZoneName
    Read-Host "Enter..."
}

function Check-Status {
    cls
    Write-Host "=== STATUS DETALLADO (WINDOWS) ===" -ForegroundColor Yellow
    Write-Host "DHCP: " -NoNewline; (Get-Service DHCPServer).Status
    Write-Host "DNS: " -NoNewline; (Get-Service DNS).Status
    Write-Host "`n--- Zonas Cargadas ---"
    Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | Select-Object ZoneName
    Read-Host "Enter..."
}

function Ver-Red {
    Get-NetIPAddress -InterfaceAlias $INTERFACE -AddressFamily IPv4 | Select-Object IPAddress, PrefixLength
    Read-Host "Enter..."
}

# --- MENU PRINCIPAL ---
while ($true) {
    cls
    Write-Host "IP SERVER: $global:IP_FIJA" -ForegroundColor Gray
    Write-Host "1. Instalar DHCP/DNS   2. IP Fija (Server/DNS)"
    Write-Host "3. Configurar DHCP     4. Anadir Dominio"
    Write-Host "5. Eliminar Dominio    6. Listar Dominios"
    Write-Host "7. Check Status        8. Ver Red"
    Write-Host "9. Salir"
    $op = Read-Host "Seleccione opcion"
    switch ($op) {
        "1" { Instalar-Servicios }
        "2" { Establecer-IPFija }
        "3" { Configurar-DHCP }
        "4" { Add-Dominio }
        "5" { Del-Dominio }
        "6" { Listar-Dominios }
        "7" { Check-Status }
        "8" { Ver-Red }
        "9" { exit }
    }
}