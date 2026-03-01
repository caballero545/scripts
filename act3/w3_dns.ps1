# ---------- FUNCION 1 ----------
function Install-Roles {
    Clear-Host
    Write-Host "=== INSTALACION DHCP Y DNS ===" -ForegroundColor Cyan

    # DHCP
    $dhcp = Get-WindowsFeature DHCP
    if ($dhcp.Installed) {
        Write-Host "DHCP ya esta instalado." -ForegroundColor Yellow
        $resp = Read-Host "Deseas REINSTALAR DHCP? (y/n)"
        if ($resp -match "^[yY]$") {
            Uninstall-WindowsFeature DHCP -IncludeManagementTools
            Install-WindowsFeature DHCP -IncludeManagementTools
        }
    }
    else {
        Install-WindowsFeature DHCP -IncludeManagementTools
    }

    # DNS
    $dns = Get-WindowsFeature DNS
    if ($dns.Installed) {
        Write-Host "DNS ya esta instalado." -ForegroundColor Yellow
        $resp = Read-Host "Deseas REINSTALAR DNS? (y/n)"
        if ($resp -match "^[yY]$") {
            Uninstall-WindowsFeature DNS -IncludeManagementTools
            Install-WindowsFeature DNS -IncludeManagementTools
        }
    }
    else {
        Install-WindowsFeature DNS -IncludeManagementTools
    }

    Write-Host "Proceso completado." -ForegroundColor Green
    Read-Host "Presiona Enter..."
}
# ---------- FUNCION 2 ----------

function Configure-Network-Services {

    Clear-Host
    Write-Host "=== CONFIGURACION DHCP + DNS ESTABLE ===" -ForegroundColor Yellow

    # IP SERVIDOR
    $ip_srv = Read-Host "IP del servidor (ej 192.168.10.10)"
    $mask = Read-Host "Mascara (Enter = 255.255.255.0)"
    if ([string]::IsNullOrWhiteSpace($mask)) { $mask = "255.255.255.0" }

    $gateway = Read-Host "Gateway (Enter para omitir)"

    # RANGO DHCP
    $IP_INI_REAL = Read-Host "IP inicio rango DHCP (ej 192.168.10.20)"
    $IP_FIN_REAL = Read-Host "IP fin rango DHCP (ej 192.168.10.30)"

    # TIEMPO DE CONCESION EN SEGUNDOS
    $leaseSeconds = Read-Host "Tiempo de concesion en segundos (ej 3600)"
    if (-not [int]::TryParse($leaseSeconds, [ref]$null)) {
        Write-Host "Tiempo invalido. Se usara 3600 segundos." -ForegroundColor Yellow
        $leaseSeconds = 3600
    }

    $LEASE_TIME = New-TimeSpan -Seconds $leaseSeconds

    # INTERFAZ ACTIVA
    $interface = Get-NetAdapter | Where {$_.Status -eq "Up"} | Select -First 1
    $ifName = $interface.Name

    # LIMPIAR IPs
    Get-NetIPAddress -InterfaceAlias $ifName -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue

    Start-Sleep 2

    # ASIGNAR IP FIJA
    try {
        if ($gateway) {
            New-NetIPAddress -InterfaceAlias $ifName -IPAddress $ip_srv -PrefixLength 24 -DefaultGateway $gateway -ErrorAction Stop
        }
        else {
            New-NetIPAddress -InterfaceAlias $ifName -IPAddress $ip_srv -PrefixLength 24 -ErrorAction Stop
        }
    }
    catch {
        Write-Host "Error asignando IP. Puede estar en uso." -ForegroundColor Red
        Read-Host "Enter..."
        return
    }

    Start-Sleep 3

    # EL SERVIDOR SE USA COMO DNS
    Set-DnsClientServerAddress -InterfaceAlias $ifName -ServerAddresses $ip_srv

    Restart-Service DNS -ErrorAction SilentlyContinue
    Start-Sleep 3

    # ZONA REVERSA
    $networkID = ($ip_srv.Split(".")[0..2] -join ".")
    if (-not (Get-DnsServerZone | Where {$_.ZoneName -like "*in-addr.arpa"})) {
        Add-DnsServerPrimaryZone -NetworkID "$networkID/24"
    }

    # VERIFICAR DNS
    try {
        Resolve-DnsName localhost -Server $ip_srv -ErrorAction Stop
    }
    catch {
        Write-Host "DNS no responde correctamente." -ForegroundColor Red
        Read-Host "Enter..."
        return
    }

    # BORRAR AMBITOS ANTERIORES
    Get-DhcpServerv4Scope -ErrorAction SilentlyContinue |
        ForEach-Object { Remove-DhcpServerv4Scope -ScopeId $_.ScopeId -Force }

    # CREAR AMBITO
    Add-DhcpServerv4Scope -Name "Scope_Principal" `
        -StartRange $IP_INI_REAL `
        -EndRange $IP_FIN_REAL `
        -SubnetMask $mask `
        -LeaseDuration $LEASE_TIME `
        -State Active

    Start-Sleep 2

    $scopeId = (Get-DhcpServerv4Scope | Where {$_.Name -eq "Scope_Principal"}).ScopeId

    Set-DhcpServerv4Binding -InterfaceAlias $ifName -BindingState $true

    # OPTION 006 DNS
    Set-DhcpServerv4OptionValue -ScopeId $scopeId -OptionId 6 -Value $ip_srv -Force

    # OPTION 003 ROUTER
    if ($gateway) {
        Set-DhcpServerv4OptionValue -ScopeId $scopeId -OptionId 3 -Value $gateway -Force
    }

    Restart-Service DHCPServer
    Restart-Service DNS

    Write-Host "`n=== DHCP Y DNS CONFIGURADOS CORRECTAMENTE ===" -ForegroundColor Green
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