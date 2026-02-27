# ============================================
#   ADMINISTRADOR DHCP + DNS (SERVER CORE)
# ============================================

# ---------- FUNCION 1 ----------
function Install-Roles {
    Clear-Host
    Write-Host "=== INSTALANDO DHCP Y DNS ===" -ForegroundColor Cyan
    
    $dhcp = Get-WindowsFeature DHCP
    $dns  = Get-WindowsFeature DNS

    if (-not $dhcp.Installed) {
        Install-WindowsFeature DHCP -IncludeManagementTools
    }

    if (-not $dns.Installed) {
        Install-WindowsFeature DNS -IncludeManagementTools
    }

    Write-Host "Roles verificados/instalados correctamente." -ForegroundColor Green
    Read-Host "Presiona Enter..."
}

# ---------- FUNCION 2 ----------
function Configure-Network-Services {
    Clear-Host
    Write-Host "=== CONFIGURACION DHCP + DNS ===" -ForegroundColor Yellow

    # RANGO IP
    while($true){
        $IP_INI = Read-Host "IP Inicial (ej. 192.168.100.20)"
        if([ipaddress]::TryParse($IP_INI,[ref]$null) -and
           $IP_INI -ne "0.0.0.0" -and
           $IP_INI -ne "255.255.255.255" -and
           $IP_INI -ne "127.0.0.0" -and
           $IP_INI -ne "127.0.0.1"){
            break
        }
        Write-Host "IP invalida o reservada." -ForegroundColor Red
    }

    while($true){
        $IP_FIN = Read-Host "IP Final (ej. 192.168.100.30)"
        if([ipaddress]::TryParse($IP_FIN,[ref]$null) -and
           $IP_FIN -ne "0.0.0.0" -and
           $IP_FIN -ne "255.255.255.255" -and
           $IP_FIN -ne "127.0.0.0" -and
           $IP_FIN -ne "127.0.0.1"){
            break
        }
        Write-Host "IP invalida o reservada." -ForegroundColor Red
    }

    $SEGMENTO = ($IP_INI -split '\.')[0..2] -join '.'

    $ip_srv = $IP_INI
    $octeto = [int]($IP_INI.Split(".")[3]) + 1
    $IP_INI_REAL = "$SEGMENTO.$octeto"

    # MASCARA
    while($true){
        $mask = Read-Host "Mascara (ej. 255.255.255.0)"
        if([ipaddress]::TryParse($mask,[ref]$null)){ break }
        Write-Host "Mascara invalida." -ForegroundColor Red
    }

    # Gateway opcional
    $gateway = Read-Host "Gateway (Enter para omitir)"
    if($gateway){
        if(-not ([ipaddress]::TryParse($gateway,[ref]$null)) -or
           $gateway -eq "1.0.0.0" -or
           $gateway -eq "255.255.255.255"){
            Write-Host "Gateway invalido." -ForegroundColor Red
            return
        }
    }

    # DNS primario
    $dns1 = Read-Host "DNS Primario (Enter para omitir)"
    if($dns1){
        if(-not ([ipaddress]::TryParse($dns1,[ref]$null)) -or
           $dns1 -eq "1.0.0.0" -or
           $dns1 -eq "255.255.255.255"){
            Write-Host "DNS Primario invalido." -ForegroundColor Red
            return
        }
    }

    $dns2 = ""
    if($dns1){
        $dns2 = Read-Host "DNS Secundario (Enter para omitir)"
        if($dns2){
            if(-not ([ipaddress]::TryParse($dns2,[ref]$null)) -or
               $dns2 -eq "1.0.0.0" -or
               $dns2 -eq "255.255.255.255"){
                Write-Host "DNS Secundario invalido." -ForegroundColor Red
                return
            }
        }
    }

    while($true){
    	$lease = Read-Host "Tiempo concesion en minutos"
    
    	if($lease -match "^[0-9]+$" -and [int]$lease -gt 0){
        $LEASE_TIME = [TimeSpan]::FromMinutes([int]$lease)
        break
    	}

    Write-Host "Debe ingresar un numero entero positivo mayor a 0." -ForegroundColor Red
    }

    $interface = Get-NetAdapter | Where {$_.Status -eq "Up"} | Select -First 1

    Remove-NetIPAddress -InterfaceAlias $interface.Name -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias $interface.Name -IPAddress $ip_srv -PrefixLength 24 -DefaultGateway $gateway -ErrorAction SilentlyContinue

    Add-DhcpServerv4Scope -Name "Scope_Principal" -StartRange $IP_INI_REAL -EndRange $IP_FIN -SubnetMask $mask -LeaseDuration $LEASE_TIME -ErrorAction SilentlyContinue

    Set-DhcpServerv4Binding -InterfaceAlias $interface.Name -BindingState $true

    if($dns1){
        if($dns2){
            Set-DhcpServerv4OptionValue -OptionId 6 -Value $dns1,$dns2
        } else {
            Set-DhcpServerv4OptionValue -OptionId 6 -Value $dns1
        }
    }

    Restart-Service DHCPServer
    Restart-Service DNS

    Write-Host "Configuracion aplicada correctamente." -ForegroundColor Green
    Read-Host "Presiona Enter..."
}
# ---------- FUNCION 3 ----------
function Check-Status {
    Clear-Host
    Write-Host "=== ESTADO SERVICIOS ===" -ForegroundColor Cyan
    
    Get-Service DHCPServer | Select Status,DisplayName
    Get-Service DNS | Select Status,DisplayName

    Write-Host "`n=== DOMINIOS CONFIGURADOS ===" -ForegroundColor Yellow
    $zones = Get-DnsServerZone | Where {$_.ZoneType -eq "Primary"}

    if($zones){
        foreach($z in $zones){
            Write-Host "Dominio: $($z.ZoneName)"
        }
    } else {
        Write-Host "No hay dominios creados."
    }

    Read-Host "Presiona Enter..."
}

# ---------- FUNCION 4 ----------
function Create-Domain {
    Clear-Host
    Write-Host "=== CREAR DOMINIO ===" -ForegroundColor Cyan

    $domain = Read-Host "Nombre dominio (ej. empresa.local)"

    if(Get-DnsServerZone -Name $domain -ErrorAction SilentlyContinue){
        Write-Host "El dominio ya existe." -ForegroundColor Red
        Read-Host "Enter..."
        return
    }

    Add-DnsServerPrimaryZone -Name $domain -ZoneFile "$domain.dns"

    while($true){
        $ip = Read-Host "IP para el dominio"
        if([ipaddress]::TryParse($ip,[ref]$null) -and
           $ip -ne "0.0.0.0" -and
           $ip -ne "255.255.255.255" -and
           $ip -ne "127.0.0.0" -and
           $ip -ne "127.0.0.1"){
            break
        }
        Write-Host "IP invalida o reservada."
    }

    Add-DnsServerResourceRecordA -ZoneName $domain -Name "@" -IPv4Address $ip

    Write-Host "Dominio creado correctamente." -ForegroundColor Green
    Read-Host "Enter..."
}

# ---------- FUNCION 5 ----------
function Show-Domains {
    Clear-Host
    Write-Host "=== LISTA DOMINIOS ===" -ForegroundColor Yellow

    $zones = Get-DnsServerZone | Where {$_.ZoneType -eq "Primary"}

    if($zones){
        $zones | Select ZoneName | Format-Table -AutoSize
    } else {
        Write-Host "No hay dominios."
    }

    Read-Host "Enter..."
}

# ---------- FUNCION 6 ----------
function Delete-Domain {
    Clear-Host
    Write-Host "=== ELIMINAR DOMINIO ===" -ForegroundColor Red

    $domain = Read-Host "Dominio a eliminar"

    if(-not (Get-DnsServerZone -Name $domain -ErrorAction SilentlyContinue)){
        Write-Host "Dominio no existe." -ForegroundColor Red
        Read-Host "Enter..."
        return
    }

    Remove-DnsServerZone -Name $domain -Force

    Write-Host "Dominio eliminado correctamente." -ForegroundColor Green
    Read-Host "Enter..."
}

# ---------- MENU ----------
while($true){
    Clear-Host
    Write-Host "----------------------------------"
    Write-Host " ADMINISTRADOR DHCP + DNS SERVER "
    Write-Host "----------------------------------"
    Write-Host "1. Instalar DHCP y DNS"
    Write-Host "2. Configuracion DHCP y DNS"
    Write-Host "3. Check Status"
    Write-Host "4. Crear Dominio"
    Write-Host "5. Consultar Dominios"
    Write-Host "6. Eliminar Dominio"
    Write-Host "7. Salir"

    $op = Read-Host "Seleccione opcion"

    switch($op){
        "1" { Install-Roles }
        "2" { Configure-Network-Services }
        "3" { Check-Status }
        "4" { Create-Domain }
        "5" { Show-Domains }
        "6" { Delete-Domain }
        "7" { exit }
        default { Write-Host "Opcion invalida."; Start-Sleep 1 }
    }
}