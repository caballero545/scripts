# --- VARIABLES GLOBALES ---
$global:IP_FIJA = ""
$global:INTERFACE = "Ethernet 2" 
$global:SEGMENTO = ""
$global:OCT_SRV = 0

# --- FUNCION DE LIMPIEZA ---
function Limpiar-ZonasBasura {
    Write-Host "Limpiando configuracion DNS..." -ForegroundColor Gray
}

# --- 1. INSTALACION ---
function Instalar-Servicios {
    Clear-Host
    Write-Host "--- Instalando Roles DHCP y DNS ---" -ForegroundColor Cyan
    Install-WindowsFeature -Name DHCP, DNS -IncludeManagementTools
    Write-Host "Roles instalados correctamente."
    Read-Host "Presione Enter para volver"
}

# --- 2. IP FIJA Y ACTIVACION DNS ---
function Establecer-IPFija {
    Clear-Host
    Write-Host "--- Configurar IP Fija ---" -ForegroundColor Cyan
    while ($true) {
        $IP_ING = Read-Host "Ingrese la IP Fija (ej. 11.11.11.2) o [r]"
        if ($IP_ING -eq "r") { return }

        # Validacion: Solo formato IP (4 bloques de 1-3 numeros)
        if ($IP_ING -match "^\d{1,3}(\.\d{1,3}){3}$") {
            $global:IP_FIJA = $IP_ING
            $Octetos = $IP_FIJA.Split('.')
            $global:SEGMENTO = "$($Octetos[0]).$($Octetos[1]).$($Octetos[2])"
            $global:OCT_SRV = [int]$Octetos[3]

            New-NetIPAddress -InterfaceAlias $global:INTERFACE -IPAddress $global:IP_FIJA -PrefixLength 24 -DefaultGateway "$global:SEGMENTO.1" -ErrorAction SilentlyContinue
            Restart-Service DNS
            Write-Host "IP establecida correctamente." -ForegroundColor Green
            break
        } else {
            Write-Host "ERROR: Formato de IP invalido. Use numeros y puntos." -ForegroundColor Red
        }
    }
    Read-Host "Presione Enter..."
}

# --- 3. CONFIGURAR DHCP ---
function Configurar-DHCP {
    Clear-Host
    if ($global:IP_FIJA -eq "") { Write-Host "ERROR: Defina IP Fija primero." -ForegroundColor Red; Read-Host "Enter..."; return }

    Remove-DhcpServerv4Scope -ScopeId "$global:SEGMENTO.0" -Force -ErrorAction SilentlyContinue

    $GATEWAY = "$global:SEGMENTO.1"
    $MIN_INI = $global:OCT_SRV + 1
    Write-Host "--- Rango DHCP (Gateway: $GATEWAY) ---" -ForegroundColor Cyan

    # Validacion IP Inicial
    while ($true) {
        $IP_INI = Read-Host "IP Inicial (Minimo $global:SEGMENTO.$MIN_INI) o [r]"
        if ($IP_INI -eq "r") { return }
        if ($IP_INI -match "^\d{1,3}(\.\d{1,3}){3}$") {
            $OctIni = [int]$IP_INI.Split('.')[3]
            if ($IP_INI.StartsWith($global:SEGMENTO) -and $OctIni -ge $MIN_INI) { break }
        }
        Write-Host "ERROR: La IP debe ser del segmento $global:SEGMENTO y mayor a $global:IP_FIJA." -ForegroundColor Red
    }

    # Validacion IP Final
    while ($true) {
        $IP_FIN = Read-Host "IP Final (ej. $global:SEGMENTO.254)"
        if ($IP_FIN -match "^\d{1,3}(\.\d{1,3}){3}$") {
            $OctFin = [int]$IP_FIN.Split('.')[3]
            if ($OctFin -gt $OctIni -and $OctFin -le 254) { break }
        }
        Write-Host "ERROR: IP Final debe ser mayor a la inicial ($IP_INI) y no exceder 254." -ForegroundColor Red
    }

    # Validacion Tiempo de Concesion (No negativos, solo numeros)
    while ($true) {
        $LEASE_STR = Read-Host "Tiempo de concesion en segundos (Min 60)"
        if ($LEASE_STR -match "^\d+$" -and [int]$LEASE_STR -ge 60) {
            $LeaseTimeSpan = [TimeSpan]::FromSeconds([int]$LEASE_STR)
            break
        }
        Write-Host "ERROR: Ingrese un numero positivo (minimo 60 segundos)." -ForegroundColor Red
    }

    Add-DhcpServerv4Scope -Name "RedExamen" -StartRange $IP_INI -EndRange $IP_FIN -SubnetMask 255.255.255.0 -State Active -LeaseDuration $LeaseTimeSpan
    Set-DhcpServerv4OptionValue -OptionId 3 -Value $GATEWAY 
    Set-DhcpServerv4OptionValue -OptionId 6 -Value $global:IP_FIJA -Force

    Restart-Service DHCPServer
    Write-Host "DHCP configurado exitosamente." -ForegroundColor Green
    Read-Host "Enter..."
}

# --- 4. GESTION DE DOMINIOS ---
function Add-Dominio {
    Clear-Host
    if ($global:IP_FIJA -eq "") { Write-Host "Error: IP Fija requerida." -ForegroundColor Red; return }
    
    while ($true) {
        $DOM = Read-Host "Nombre del dominio (ej. aprobar.com)"
        # Validacion: Solo letras, numeros, puntos y guiones. No caracteres especiales.
        if ($DOM -match "^[a-zA-Z0-9][-a-zA-Z0-9.]*\.[a-zA-Z]{2,}$") { break }
        Write-Host "ERROR: Nombre de dominio invalido. No use caracteres especiales como @, $, #." -ForegroundColor Red
    }

    Add-DnsServerPrimaryZone -Name $DOM -ZoneFile "$DOM.dns" -ErrorAction SilentlyContinue
    Add-DnsServerResourceRecordA -Name "@" -IPv4Address $global:IP_FIJA -ZoneName $DOM
    Add-DnsServerResourceRecordA -Name "ns" -IPv4Address $global:IP_FIJA -ZoneName $DOM

    Restart-Service DNS
    Write-Host "Dominio $DOM creado." -ForegroundColor Green
    Read-Host "Enter..."
}
# --- (Las funciones Del-Dominio, Listar, Check-Status y Ver-Red se mantienen igual) ---

function Del-Dominio {
    Clear-Host
    $DOM_DEL = Read-Host "Ingrese el nombre EXACTO del dominio a borrar"
    if (Get-DnsServerZone -Name $DOM_DEL -ErrorAction SilentlyContinue) {
        Remove-DnsServerZone -Name $DOM_DEL -Force
        Restart-Service DNS
        Write-Host "Eliminado." -ForegroundColor Green
    } else {
        Write-Host "No existe." -ForegroundColor Yellow
    }
    Read-Host "Enter..."
}

function Listar-Dominios {
    Write-Host "--- Dominios en Servidor ---" -ForegroundColor Yellow
    Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | Select-Object ZoneName
    Read-Host "Enter..."
}

# --- 5. STATUS Y RED ---
function Check-Status {
    cls
    Write-Host "==========================================" -ForegroundColor Yellow
    Write-Host "        ESTADO DETALLADO (WINDOWS)" -ForegroundColor Yellow
    Write-Host "==========================================" -ForegroundColor Yellow
    
    Write-Host "DHCP: " -NoNewline; (Get-Service DHCPServer).Status
    Write-Host "DNS: " -NoNewline; (Get-Service DNS).Status
    
    Write-Host "`n--- Zonas Cargadas ---"
    Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | Select-Object ZoneName
    
    Write-Host "`nIP Servidor: $global:IP_FIJA"
    Read-Host "Presione Enter..."
}
function Ver-Red {
    Get-NetIPAddress -InterfaceAlias $global:INTERFACE -AddressFamily IPv4 | Select-Object IPAddress, PrefixLength
    Read-Host "Enter..."
}
# --- MENU PRINCIPAL ---
while ($true) {
    cls
    Write-Host "IP SRV (DNS/DOM): $global:IP_FIJA" -ForegroundColor Gray
    Write-Host "1. Instalar DHCP/DNS   2. IP Fija (Server/DNS)"
    Write-Host "3. Configurar DHCP     4. Anadir Dominio"
    Write-Host "5. Eliminar Dominio    6. Listar Dominios"
    Write-Host "7. Check Status        8. Ver Red"
    Write-Host "9. Cls                 10. Salir"
    
    $op = Read-Host "Seleccione"
    switch ($op) {
        "1" { Instalar-Servicios }
        "2" { Establecer-IPFija }
        "3" { Configurar-DHCP }
        "4" { Add-Dominio }
        "5" { Del-Dominio }
        "6" { Listar-Dominios; Read-Host "Enter..." }
        "7" { Check-Status; Read-Host "Enter..." }
        "8" { Ver-Red; Read-Host "Enter..." }
        "9" { cls }
        "10" { exit }
    }
}