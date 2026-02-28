# ---------- FUNCION 1 ----------
function Install-Roles {
    Clear-ScreenFix
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
    Clear-ScreenFix
    Write-Host "=== CONFIGURACION DHCP + DNS ===" -ForegroundColor Yellow

    # ---------------- IP INICIAL ----------------
    while($true){
        $IP_INI = Read-Host "IP Inicial (ej. 192.168.100.20)"
        if(
    		$IP_INI -match '^(\d{1,3}\.){3}\d{1,3}$' -and
    		($IP_INI.Split('.') | ForEach-Object {[int]$_ -ge 0 -and [int]$_ -le 255}) -notcontains $false
    	){
    		break
	}
        Write-Host "IP invalida." -ForegroundColor Red
    }

    # ---------------- IP FINAL ----------------
    while($true){
        $IP_FIN = Read-Host "IP Final (ej. 192.168.100.30)"
        if(
    		$IP_FIN -match '^(\d{1,3}\.){3}\d{1,3}$' -and
    		($IP_FIN.Split('.') | ForEach-Object {[int]$_ -ge 0 -and [int]$_ -le 255}) -notcontains $false
	){
    		break
	}
        Write-Host "IP invalida." -ForegroundColor Red
    }

    $ipObjIni = [ipaddress]$IP_INI
    $ipObjFin = [ipaddress]$IP_FIN

    if([uint32]$ipObjFin.Address -lt [uint32]$ipObjIni.Address){
        Write-Host "La IP final no puede ser menor que la inicial." -ForegroundColor Red
        Read-Host "Enter..."
        return
    }

    # ----------- IP FIJA SERVIDOR -----------
    $ip_srv = $IP_INI

    # ----------- RECORRER RANGO +1 -----------
    $iniOct = $IP_INI.Split(".")
    $finOct = $IP_FIN.Split(".")

    $iniLast = [int]$iniOct[3] + 1
    $finLast = [int]$finOct[3] + 1

    if($iniLast -gt 255 -or $finLast -gt 255){
        Write-Host "El rango excede 255 al recorrer +1." -ForegroundColor Red
        Read-Host "Enter..."
        return
    }

    $IP_INI_REAL = "$($iniOct[0]).$($iniOct[1]).$($iniOct[2]).$iniLast"
    $IP_FIN_REAL = "$($finOct[0]).$($finOct[1]).$($finOct[2]).$finLast"

    # ---------------- MASCARA ----------------
    $mask = Read-Host "Mascara (Enter para 255.255.255.0)"
    if([string]::IsNullOrWhiteSpace($mask)){
        $mask = "255.255.255.0"
    }
    elseif(-not ([ipaddress]::TryParse($mask,[ref]$null))){
        Write-Host "Mascara invalida." -ForegroundColor Red
        return
    }

    # ---------------- GATEWAY ----------------
    $gateway = Read-Host "Gateway (Enter para omitir)"
    if($gateway){
        if(-not ([ipaddress]::TryParse($gateway,[ref]$null))){
            Write-Host "Gateway invalido." -ForegroundColor Red
            return
        }
    }

    # ---------------- DNS ----------------
    $dns1 = Read-Host "DNS Primario (Enter para omitir)"
    if($dns1){
        if(-not ([ipaddress]::TryParse($dns1,[ref]$null))){
            Write-Host "DNS invalido." -ForegroundColor Red
            return
        }
    }

    $dns2 = ""
    if($dns1){
        $dns2 = Read-Host "DNS Secundario (Enter para omitir)"
        if($dns2){
            if(-not ([ipaddress]::TryParse($dns2,[ref]$null))){
                Write-Host "DNS Secundario invalido." -ForegroundColor Red
                return
            }
        }
    }
    
    Start-Service DNS -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # ---------------- LEASE ----------------
    while($true){
        $lease = Read-Host "Tiempo concesion en minutos"
        if($lease -match "^[0-9]+$" -and [int]$lease -gt 0){
            $LEASE_TIME = [TimeSpan]::FromMinutes([int]$lease)
            break
        }
        Write-Host "Debe ser numero entero positivo." -ForegroundColor Red
    }

    # ---------------- CONFIGURAR INTERFAZ ----------------
    $interface = Get-NetAdapter | Where {$_.Status -eq "Up"} | Select -First 1
    $ifName = $interface.Name

    Remove-NetIPAddress -InterfaceAlias $ifName -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias $ifName -IPAddress $ip_srv -PrefixLength 24 -DefaultGateway $gateway -ErrorAction SilentlyContinue
    
    # FIX 1: Espera obligatoria para que Windows reconozca la IP
    Start-Sleep -Seconds 5 

    # FIX 2: Configurar el DNS del propio servidor a sí mismo para validar Option 6
    Set-DnsClientServerAddress -InterfaceAlias $ifName -ServerAddresses $ip_srv

    # ---------------- DHCP SCOPE ----------------
    $existingScope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if ($existingScope) {
        foreach ($s in $existingScope) { Remove-DhcpServerv4Scope -ScopeId $s.ScopeId -Force }
    }

    Add-DhcpServerv4Scope -Name "Scope_Principal" -StartRange $IP_INI_REAL -EndRange $IP_FIN_REAL -SubnetMask $mask -LeaseDuration $LEASE_TIME
    Start-Sleep -Seconds 2

    $scopeId = (Get-DhcpServerv4Scope | Where-Object { $_.Name -eq "Scope_Principal" }).ScopeId

    # FIX 3: Reintentar el Binding si falla
    try {
        Set-DhcpServerv4Binding -InterfaceAlias $ifName -BindingState $true -ErrorAction Stop
    } catch {
        Start-Sleep -Seconds 2
        Set-DhcpServerv4Binding -InterfaceAlias $ifName -BindingState $true -ErrorAction SilentlyContinue
    }

    # Configurar DNS (Option 6) - Ahora no dará error de "Invalid"
    $dnsValues = @($ip_srv)

    if ($dns2) {
    	$dnsValues += $dns2
    }

    Set-DhcpServerv4OptionValue -ScopeId $scopeId -OptionId 6 -Value $dnsValues

    Restart-Service DHCPServer, DNS -Force
    Write-Host "`n=== CONFIGURACION APLICADA SIN ERRORES ===" -ForegroundColor Green
    Read-Host "Presiona Enter..."

}
# ---------- FUNCION 3 ----------
function Check-Status {
    Clear-ScreenFix
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
    Clear-ScreenFix
    Write-Host "=== CREAR DOMINIO ===" -ForegroundColor Cyan
    $domain = Read-Host "Nombre dominio (ej. empresa.local)"

    if(Get-DnsServerZone -Name $domain -ErrorAction SilentlyContinue){
        # FIX: Corregido el nombre del color y comillas
        Write-Host "[ERROR] El dominio ya existe." -ForegroundColor Red 
        Read-Host "Presiona Enter..."
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
    Clear-ScreenFix
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
    Clear-ScreenFix
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

function Clear-ScreenFix {
    [Console]::Clear()
    $Host.UI.RawUI.FlushInputBuffer()
}

# ---------- MENU ----------
while($true){
    Clear-ScreenFix
    Write-Host "----------------------------------"
    Write-Host " ADMINISTRADOR DHCP + DNS SERVER "
    Write-Host "----------------------------------"
    Write-Host "1. Instalar DHCP y DNS"
    Write-Host "2. Configuracion DHCP y DNS"
    Write-Host "3. Check Status"
    Write-Host "4. Crear Dominio"
    Write-Host "5. Consultar Dominios"
    Write-Host "6. Eliminar Dominio"
    Write-Host "7. Limpiar Pantalla"
    Write-Host "8. Salir"

    $op = Read-Host "Seleccione opcion"

    switch($op){
        "1" { Install-Roles }
        "2" { Configure-Network-Services }
        "3" { Check-Status }
        "4" { Create-Domain }
        "5" { Show-Domains }
        "6" { Delete-Domain }
	"7" { Clear-ScreenFix }
        "8" { exit }
        default { Write-Host "Opcion invalida."; Start-Sleep 1 }
    }
}