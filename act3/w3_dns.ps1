# --- VARIABLES GLOBALES ---
$global:IP_FIJA = ""
$global:INTERFACE = "Ethernet 2" # Asegurate que este sea el nombre de tu red
$global:SEGMENTO = ""
$global:OCT_SRV = 0
# --- FUNCION DE LIMPIEZA (Antidoto) ---
function Limpiar-ZonasBasura {
    # En Windows, las zonas se manejan como objetos. 
    # Esta funcion asegura que no existan registros corruptos o vacios.
    Write-Host "Limpiando configuracion DNS..." -ForegroundColor Gray
}
# --- 1. INSTALACION ---
function Instalar-Servicios {
    Write-Host "--- Instalando Roles DHCP y DNS ---" -ForegroundColor Cyan
    Install-WindowsFeature -Name DHCP, DNS -IncludeManagementTools
    Write-Host "Roles instalados correctamente."
    Read-Host "Presione [r] para volver"
}
# --- 2. IP FIJA Y ACTIVACION DNS ---
function Establecer-IPFija {
    Write-Host "--- Configurar IP Fija y Activar DNS ---" -ForegroundColor Cyan
    while ($true) {
        $IP_ING = Read-Host "Ingrese la IP Fija (ej. 11.11.11.2) o [r]"
        if ($IP_ING -eq "r") { return }

        if ($IP_ING -match "^\d{1,3}(\.\d{1,3}){3}$") {
            $global:IP_FIJA = $IP_ING
            $Octetos = $IP_FIJA.Split('.')
            $global:SEGMENTO = "$($Octetos[0]).$($Octetos[1]).$($Octetos[2])"
            $global:OCT_SRV = [int]$Octetos[3]

            # Aplicar IP a la interfaz
            New-NetIPAddress -InterfaceAlias $global:INTERFACE -IPAddress $global:IP_FIJA -PrefixLength 24 -DefaultGateway "$global:SEGMENTO.1" -ErrorAction SilentlyContinue
            
            # Curar y activar DNS
            Limpiar-ZonasBasura
            Restart-Service DNS
            Write-Host "IP establecida y DNS reiniciado." -ForegroundColor Green
            break
        } else {
            Write-Host "IP invalida." -ForegroundColor Red
        }
    }
    Read-Host "Presione Enter..."
}

# --- 3. CONFIGURAR DHCP ---
function Configurar-DHCP {
    if ($global:IP_FIJA -eq "") { Write-Host "ERROR: Defina IP Fija primero." -ForegroundColor Red; Read-Host "Enter..."; return }

    $GATEWAY = "$global:SEGMENTO.1"
    $MIN_INI = $global:OCT_SRV + 1
    Write-Host "--- Rango DHCP (Gateway: $GATEWAY) ---" -ForegroundColor Cyan

    while ($true) {
        $IP_INI = Read-Host "IP Inicial (Minimo $global:SEGMENTO.$MIN_INI) o [r]"
        if ($IP_INI -eq "r") { return }
        $OctIni = $IP_INI.Split('.')[3]

        if ($IP_INI.StartsWith($global:SEGMENTO) -and [int]$OctIni -ge $MIN_INI) {
            break
        } else {
            Write-Host "Error: La IP debe ser mayor a $global:IP_FIJA." -ForegroundColor Red
        }
    }

    $IP_FIN = Read-Host "IP Final (ej. $global:SEGMENTO.254)"
    $LEASE_SEG = Read-Host "Tiempo de concesion (segundos)"
    $LeaseTimeSpan = [TimeSpan]::FromSeconds($LEASE_SEG)

    # Crear Scope y opciones
    Add-DhcpServerv4Scope -Name "RedExamen" -StartRange $IP_INI -EndRange $IP_FIN -SubnetMask 255.255.255.0 -State Active -LeaseDuration $LeaseTimeSpan
    Set-DhcpServerv4OptionValue -OptionId 3 -Value $GATEWAY # Router
    Set-DhcpServerv4OptionValue -OptionId 6 -Value $global:IP_FIJA # DNS Server

    Restart-Service DHCPServer
    Write-Host "DHCP Activo! Gateway .1 y DNS en $global:IP_FIJA." -ForegroundColor Green
    Read-Host "Enter..."
}

# --- 4. GESTION DE DOMINIOS ---
function Add-Dominio {
    if ($global:IP_FIJA -eq "") { Write-Host "Error: IP Fija requerida." -ForegroundColor Red; return }
    Limpiar-ZonasBasura

    $DOM = Read-Host "Nombre del dominio o [r]"
    if ($DOM -eq "r" -or $DOM -eq "") { return }

    # Crear Zona y Registros A
    Add-DnsServerPrimaryZone -Name $DOM -ReplicationScope "None" -ErrorAction SilentlyContinue
    Add-DnsServerResourceRecordA -Name "@" -IPv4Address $global:IP_FIJA -ZoneName $DOM
    Add-DnsServerResourceRecordA -Name "ns" -IPv4Address $global:IP_FIJA -ZoneName $DOM

    Restart-Service DNS
    Write-Host "Dominio $DOM creado apuntando a $global:IP_FIJA." -ForegroundColor Green
    Read-Host "Enter..."
}

function Del-Dominio {
    $DOM_DEL = Read-Host "Ingrese el nombre EXACTO del dominio a borrar"
    if ($DOM_DEL -eq "") { return }

    # Validacion de existencia
    if (Get-DnsServerZone -Name $DOM_DEL -ErrorAction SilentlyContinue) {
        Write-Host "Eliminando UNICAMENTE $DOM_DEL..."
        # Borrado de objeto exacto (No borra parecidos)
        Remove-DnsServerZone -Name $DOM_DEL -Force
        
        Limpiar-ZonasBasura
        Restart-Service DNS
        Write-Host "Dominio $DOM_DEL eliminado correctamente." -ForegroundColor Green
    } else {
        Write-Host "El dominio $DOM_DEL no existe." -ForegroundColor Red
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
    Write-Host "9. Cls		       10. Salir"
    
    $op = Read-Host "Seleccione"
    switch ($op) {
        "1" { Instalar-Servicios }
        "2" { Establecer-IPFija }
        "3" { Configurar-DHCP }
        "4" { Add-Dominio }
        "5" { Del-Dominio }
        "6" { Listar-Dominios }
        "7" { Check-Status }
        "8" { Ver-Red }
	"9" { cls; Write-Host "Pantalla limpia."; Start-Sleep -Seconds 1 }
        "10" { exit }
    }
}