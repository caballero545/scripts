# --- FUNCIÓN 1: INSTALAR/VERIFICAR ROL DHCP ---
function Download-Update-DHCP {
    Write-Host "--- Verificando Rol DHCP ---" -ForegroundColor Cyan
    $check = Get-WindowsFeature -Name DHCP
    if ($check.Installed -eq $false) {
        Write-Host "Instalando Rol DHCP..."
        Install-WindowsFeature -Name DHCP -IncludeManagementTools
    } else {
        Write-Host "El Rol DHCP ya está instalado."
    }
    Read-Host "Presiona [Enter] para volver al menú..."
}
# --- FUNCIÓN 2: CONFIGURAR PARÁMETROS ---
function Configure-DHCP-Range {
    Write-Host "--- Configuracion de Parametros DHCP ---" -ForegroundColor Yellow
    
    # 1. IP Inicial
    while($true) {
        $global:IP_INI = Read-Host "Ingrese la IP Inicial (ej. 112.12.12.2)"
        if ([ipaddress]::TryParse($IP_INI, [ref]$null) -and $IP_INI -notmatch "^127\.") {
            $global:SEGMENTO = ($IP_INI -split '\.')[0..2] -join '.'
            break
        }
        Write-Host "Error: IP invalida o reservada." -ForegroundColor Red
    }

    # 2. IP Final
    while($true) {
        $global:IP_FIN = Read-Host "Ingrese la IP Final (ej. 112.12.12.12)"
        if ([ipaddress]::TryParse($IP_FIN, [ref]$null)) {
            $seg_fin = ($IP_FIN -split '\.')[0..2] -join '.'
            if ($seg_fin -eq $SEGMENTO) { break }
            Write-Host "Error: Debe estar en la red $SEGMENTO.x" -ForegroundColor Red
        } else { Write-Host "Error: IP inválida." -ForegroundColor Red }
    }

    # 3. Gateway y DNS (Opcionales)
    $global:GATEWAY = Read-Host "Ingrese Gateway (Opcional, Enter para omitir)"
    $global:DNS_SRV = Read-Host "Ingrese DNS (Opcional, Enter para omitir)"

    # 4. Tiempo de Concesión (Validar positivo)
    while($true) {
    $lease = Read-Host "Tiempo de concesion en minutos"
    # Validamos usando una expresión regular (solo números) para evitar errores de casteo
    	if ($lease -match "^[0-9]+$" -and [int]$lease -gt 0) {
        	$global:LEASE_TIME = [TimeSpan]::FromMinutes([int]$lease)
        	break
    	}
    Write-Host "Error: Ingrese un numero entero positivo." -ForegroundColor Red
    }

    Write-Host "CONFIGURACION LISTA PARA APLICAR" -ForegroundColor Green
    Write-Host "Rango: $IP_INI - $IP_FIN"
    Read-Host "Presiona [Enter] para aplicar cambios..."
    Apply-DHCP-Config
}
# --- FUNCIÓN 3: APLICAR EN WINDOWS SERVER ---
function Apply-DHCP-Config {
    try {
        # 1. Seleccionar el SEGUNDO adaptador activo
        # Usamos -Skip 1 para saltarnos el primero y agarrar el segundo
        $interface = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -Skip 1 -First 1
        
        if (-not $interface) {
            Write-Host "Error: No se encontró un segundo adaptador de red activo." -ForegroundColor Red
            return
        }

        $ip_srv = "$SEGMENTO.1"
        
        Write-Host "Configurando IP $ip_srv en $($interface.Name) (Segundo Adaptador)..." -ForegroundColor Cyan
        
        # Limpiamos IPs viejas en esa tarjeta para evitar el error de "IP ya existe"
        Remove-NetIPAddress -InterfaceAlias $interface.Name -Confirm:$false -ErrorAction SilentlyContinue

        # Asignamos la nueva IP
        New-NetIPAddress -InterfaceAlias $interface.Name -IPAddress $ip_srv -PrefixLength 24 -ErrorAction SilentlyContinue

        # 2. Crear el Ámbito (Scope) en el DHCP
        Add-DhcpServerv4Scope -Name "Red_Automatizada" -StartRange $IP_INI -EndRange $IP_FIN -SubnetMask 255.255.255.0 -LeaseDuration $LEASE_TIME
        
        # 3. Vincular el servicio DHCP específicamente a esta tarjeta (BINDING)
        # Esto soluciona el problema de que el DHCP escuche por donde no debe
        Set-DhcpServerv4Binding -InterfaceAlias $interface.Name -BindingState $true
        Restart-Service DHCPServer

        # 4. Opciones de Gateway y DNS
        if ($GATEWAY) { Set-DhcpServerv4OptionValue -OptionId 3 -Value $GATEWAY }
        if ($DNS_SRV) { Set-DhcpServerv4OptionValue -OptionId 6 -Value $DNS_SRV }

        Write-Host "¡SERVIDOR DHCP ACTIVO EN $($interface.Name)!" -ForegroundColor Green
    } catch {
        Write-Host "Error al aplicar: $($_.Exception.Message)" -ForegroundColor Red
    }
    Read-Host "Presiona [Enter] para volver..."
}

# --- FUNCIÓN 4: MONITOREAR ---
function Monitor-DHCP {
    Clear-Host
    Write-Host "=== ESTADO DEL SERVIDOR DHCP ===" -ForegroundColor Cyan
    Get-Service -Name DHCPServer | Select-Object Status, DisplayName
    
    Write-Host "`n--- Ambitos Detectados ---" -ForegroundColor Yellow
    # Obtenemos todos los ambitos configurados en el servidor
    $ambitos = Get-DhcpServerv4Scope
    
    if ($ambitos) {
        foreach ($ambito in $ambitos) {
            Write-Host "`nRevisando Scope: $($ambito.ScopeId) ($($ambito.Name))" -ForegroundColor White
            $leases = Get-DhcpServerv4Lease -ScopeId $ambito.ScopeId -ErrorAction SilentlyContinue
            if ($leases) {
                $leases | Select-Object IPAddress, ClientId, HostName, AddressState | Format-Table -AutoSize
            } else {
                Write-Host "No hay clientes conectados en este ambito aun." -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "No se encontraron ambitos configurados en el servidor." -ForegroundColor Red
    }
    Read-Host "`nPresiona [Enter] para volver al menu..."
}
# --- FUNCION 5: VER ESTADO DE RED (IPCONFIG) ---
function Show-Network-Status {
    Clear-Host
    Write-Host "=== ESTADO DE RED ACTUAL ===" -ForegroundColor Cyan
    ipconfig | Select-String "IPv4", "Ethernet", "Gateway"
    Write-Host "`n--- Adaptadores Detectados ---"
    Get-NetAdapter | Select-Object Name, Status, LinkSpeed | Format-Table -AutoSize
    Read-Host "`nPresiona [Enter] para volver..."
}

# --- MENÚ PRINCIPAL ---
while($true) {
    Clear-Host
    Write-Host "------------------------------------------"
    Write-Host "   MENU DE ADMINISTRACION DHCP (WINDOWS)"
    Write-Host "------------------------------------------"
    Write-Host "1. Instalar Rol DHCP"
    Write-Host "2. Configurar y Activar Ámbito"
    Write-Host "3. Monitorear Clientes"
    Write-Host "4. ipconfig"
    Write-Host "5. Salir"
    
    $op = Read-Host "Seleccione una opción"
    switch ($op) {
        "1" { Download-Update-DHCP }
        "2" { Configure-DHCP-Range }
        "3" { Monitor-DHCP }
	"4" { Show-Network-Status }
        "5" { exit }
        default { Write-Host "Opción inválida." }
    }
}