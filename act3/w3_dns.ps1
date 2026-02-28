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

    $ip_srv = $IP_INI

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

    # ---------------- GATEWAY ----------------
    $gateway = Read-Host "Gateway (Enter para omitir)"

    # ---------------- DNS ----------------
    $dns1 = Read-Host "DNS Primario (Enter para omitir)"
    $dns2 = ""
    if($dns1){
        $dns2 = Read-Host "DNS Secundario (Enter para omitir)"
    }

    # ---------------- INICIAR DNS ----------------
    Start-Service DNS -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # ================== FIX DNS 1 ==================
    # Forzar DNS a escuchar en la IP real del servidor
    Set-DnsServerSetting -ListenAddresses $ip_srv
    Restart-Service DNS
    Start-Sleep -Seconds 3

    # ================== FIX DNS 2 ==================
    # Crear zona reversa automática
    $networkID = ($ip_srv.Split(".")[0..2] -join ".")
    $reverseZone = ($networkID.Split(".")[2..0] -join ".") + ".in-addr.arpa"

    if (-not (Get-DnsServerZone -Name $reverseZone -ErrorAction SilentlyContinue)) {
        Add-DnsServerPrimaryZone -NetworkID "$networkID/24" -ZoneFile "$reverseZone.dns"
    }

    # ================== FIX DNS 3 ==================
    # Agregar forwarder público
    Set-DnsServerForwarder -IPAddress 8.8.8.8 -PassThru -ErrorAction SilentlyContinue

    # ================== FIX DNS 4 ==================
    # Esperar hasta que DNS responda realmente
    $dnsReady = $false
    for ($i=0; $i -lt 10; $i++) {
        try {
            Resolve-DnsName localhost -Server $ip_srv -ErrorAction Stop
            $dnsReady = $true
            break
        } catch {
            Start-Sleep -Seconds 1
        }
    }

    if (-not $dnsReady) {
        Write-Host "DNS no pudo iniciar correctamente." -ForegroundColor Red
        Read-Host "Enter..."
        return
    }

    # ---------------- LEASE ----------------
    while($true){
        $lease = Read-Host "Tiempo concesion en minutos"
        if($lease -match "^[0-9]+$" -and [int]$lease -gt 0){
            $LEASE_TIME = [TimeSpan]::FromMinutes([int]$lease)
            break
        }
        Write-Host "Debe ser numero entero positivo." -ForegroundColor Red
    }

    # ---------------- INTERFAZ ----------------
    $interface = Get-NetAdapter | Where {$_.Status -eq "Up"} | Select -First 1
    $ifName = $interface.Name

    Remove-NetIPAddress -InterfaceAlias $ifName -Confirm:$false -ErrorAction SilentlyContinue
    New-NetIPAddress -InterfaceAlias $ifName -IPAddress $ip_srv -PrefixLength 24 -DefaultGateway $gateway -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 5
    Set-DnsClientServerAddress -InterfaceAlias $ifName -ServerAddresses $ip_srv

    # ---------------- DHCP ----------------
    $existingScope = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if ($existingScope) {
        foreach ($s in $existingScope) { Remove-DhcpServerv4Scope -ScopeId $s.ScopeId -Force }
    }

    Add-DhcpServerv4Scope -Name "Scope_Principal" -StartRange $IP_INI_REAL -EndRange $IP_FIN_REAL -SubnetMask $mask -LeaseDuration $LEASE_TIME
    Start-Sleep -Seconds 2

    $scopeId = (Get-DhcpServerv4Scope | Where-Object { $_.Name -eq "Scope_Principal" }).ScopeId

    Set-DhcpServerv4Binding -InterfaceAlias $ifName -BindingState $true -ErrorAction SilentlyContinue

    $dnsValues = @($ip_srv)
    if ($dns2) { $dnsValues += $dns2 }

    Set-DhcpServerv4OptionValue -ScopeId $scopeId -OptionId 6 -Value $dnsValues

    Restart-Service DHCPServer, DNS -Force

    Write-Host "`n=== CONFIGURACION APLICADA SIN ERRORES ===" -ForegroundColor Green
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

function Clear-ScreenFix {
    [Console]::Clear()
    $Host.UI.RawUI.FlushInputBuffer()
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
    Write-Host "7. limpiar pantalla"
    Write-Host "8. Salir"

    $op = Read-Host "Seleccione opcion"

    switch($op){
        "1" { Install-Roles }
        "2" { Configure-Network-Services }
        "3" { Check-Status }
        "4" { Create-Domain }
        "5" { Show-Domains }
        "6" { Delete-Domain }
	"7" { Clear-Host }
        "8" { exit }
        default { Write-Host "Opcion invalida."; Start-Sleep 1 }
    }
}