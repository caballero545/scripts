# ==============================================================
# ARCHIVO DE FUNCIONES: Whttp.ps1
# Provisionador HTTP - Windows Server
# Requiere: provisioner_windows.ps1 como main script
# Ejecutar como Administrador via SSH o PowerShell elevado
# ==============================================================

$LOG = "C:\http_provision.log"

# --------------------------------------------------------------
# LOG / DISPLAY
# --------------------------------------------------------------
function Write-Log    { param([string]$M) $T = Get-Date -Format "yyyy-MM-dd HH:mm:ss"; Add-Content -Path $LOG -Value "$T | $M" -Encoding UTF8 -ErrorAction SilentlyContinue; Write-Host $M }
function Write-LogOK  { param([string]$M) Write-Log "  [OK]  $M" }
function Write-LogErr { param([string]$M) Write-Log "  [ERR] $M" }
function Write-LogInf { param([string]$M) Write-Log "  [~]   $M" }
function Write-LogWar { param([string]$M) Write-Log "  [!]   $M" }

# --------------------------------------------------------------
# VERIFICAR PRIVILEGIOS DE ADMINISTRADOR
# --------------------------------------------------------------
function Assert-Admin {
    $current   = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($current)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-LogErr "Debes ejecutar este script como Administrador."
        exit 1
    }
}

# --------------------------------------------------------------
# INSTALAR / VERIFICAR CHOCOLATEY
# (equivalente a fix_apt en Linux)
# --------------------------------------------------------------
function Initialize-Chocolatey {
    Write-LogInf "Verificando Chocolatey..."

    # Recargar PATH antes de buscar choco
    # (por si ya estaba instalado pero esta sesion no lo tiene en PATH)
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")

    # Si choco ya funciona, no hacer nada
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-LogOK "Chocolatey disponible: $(choco --version 2>&1 | Select-Object -First 1)"
        return
    }

    # Detectar residuos de instalacion incompleta (causa del ciclo)
    Write-LogInf "choco no encontrado. Revisando residuos de instalaciones anteriores..."

    $chocoInstallDir = "C:\ProgramData\chocolatey"
    $chocoTempDirs   = @(
        "$env:TEMP\chocolatey",
        "$env:LOCALAPPDATA\Temp\chocolatey",
        "C:\Users\Administrator\AppData\Local\Temp\chocolatey"
    )

    $tieneResiduo = $false

    # Caso 1: directorio choco existe pero el binario no funciona = instalacion corrupta
    if (Test-Path "$chocoInstallDir\choco.exe") {
        $testOut = & "$chocoInstallDir\choco.exe" --version 2>&1
        if ($LASTEXITCODE -ne 0 -or ($testOut -notmatch '^\d')) {
            Write-LogWar "Instalacion corrupta de Chocolatey detectada en $chocoInstallDir"
            $tieneResiduo = $true
        }
    }

    # Caso 2: carpetas temporales del instalador de ciclos previos
    foreach ($d in $chocoTempDirs) {
        if (Test-Path $d) {
            Write-LogWar "Residuo temporal encontrado: $d"
            $tieneResiduo = $true
        }
    }

    if ($tieneResiduo) {
        Write-LogInf "Limpiando residuos antes de instalar..."

        foreach ($d in $chocoTempDirs) {
            Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
        }

        # Si el directorio principal esta corrupto, borrarlo
        if (Test-Path "$chocoInstallDir\choco.exe") {
            $testOut = & "$chocoInstallDir\choco.exe" --version 2>&1
            if ($LASTEXITCODE -ne 0 -or ($testOut -notmatch '^\d')) {
                Remove-Item $chocoInstallDir -Recurse -Force -ErrorAction SilentlyContinue
                [Environment]::SetEnvironmentVariable("ChocolateyInstall", $null, "Machine")
                [Environment]::SetEnvironmentVariable("ChocolateyInstall", $null, "User")
            }
        }

        Write-LogOK "Residuos limpiados"
    } else {
        Write-LogInf "Sin residuos. Procediendo con instalacion limpia..."
    }

    # Instalar Chocolatey descargando el script a archivo (evita el ciclo del iex directo)
    Write-LogInf "Instalando Chocolatey..."
    try {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

        $installerPath = "$env:TEMP\choco_install_once.ps1"
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile('https://community.chocolatey.org/install.ps1', $installerPath)

        if (-not (Test-Path $installerPath) -or (Get-Item $installerPath).Length -lt 1000) {
            Write-LogErr "No se pudo descargar el instalador. Verifica conexion a internet."
            exit 1
        }

        # Ejecutar el instalador una sola vez como proceso separado
        $proc = Start-Process powershell.exe `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$installerPath`"" `
            -Wait -PassThru -NoNewWindow
        Remove-Item $installerPath -Force -ErrorAction SilentlyContinue

        if ($proc.ExitCode -ne 0) {
            Write-LogErr "El instalador de Chocolatey termino con error (ExitCode: $($proc.ExitCode))"
            exit 1
        }

        # Recargar PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")

        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-LogOK "Chocolatey instalado: $(choco --version 2>&1 | Select-Object -First 1)"
        } else {
            Write-LogErr "Chocolatey no quedo en PATH. Abre una nueva ventana de PowerShell y reintenta."
            exit 1
        }

    } catch {
        Write-LogErr "Error instalando Chocolatey: $_"
        exit 1
    }
}

# --------------------------------------------------------------
# RECARGAR PATH (util tras instalar paquetes con choco)
# --------------------------------------------------------------
function Refresh-EnvPath {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

# --------------------------------------------------------------
# LIMPIAR REGLAS FIREWALL WEB ANTERIORES
# (equivalente a clean_firewall_ports en Linux)
# Solo borra reglas creadas por este script (prefijo HTTP-Prov-)
# Deja intactas RDP (3389), SSH (22) y demas del sistema
# --------------------------------------------------------------
function Clear-WebFirewallRules {
    Write-LogInf "Limpiando reglas firewall web anteriores (HTTP-Prov-*)..."

    $rules = Get-NetFirewallRule -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -like "HTTP-Prov-*" }

    foreach ($r in $rules) {
        Remove-NetFirewallRule -Name $r.Name -ErrorAction SilentlyContinue
        Write-LogInf "  Regla eliminada: $($r.DisplayName)"
    }

    Write-LogOK "Firewall web limpio"
}

# --------------------------------------------------------------
# PREPARAR ENTORNO
# (equivalente a prepare_environment en Linux)
# --------------------------------------------------------------
function Initialize-Environment {
    Write-Log "=== Preparando entorno ==="

    Assert-Admin
    Initialize-Chocolatey
    Clear-WebFirewallRules

    # Asegurar modulo WebAdministration disponible (para IIS)
    if (-not (Get-Module -ListAvailable -Name WebAdministration -ErrorAction SilentlyContinue)) {
        Write-LogInf "Importando WebAdministration..."
        Import-Module WebAdministration -ErrorAction SilentlyContinue
    }

    Write-LogOK "Entorno listo"
    Write-Host ""
}

# --------------------------------------------------------------
# VALIDAR PUERTO
# (equivalente a validate_port en Linux)
# --------------------------------------------------------------
function Test-PortAvailable {
    param([string]$P)

    if ($P -notmatch '^\d+$') {
        Write-LogWar "Solo numeros."
        return $false
    }

    $n = [int]$P

    if ($n -lt 1 -or $n -gt 65535) {
        Write-LogWar "Rango invalido (1-65535)."
        return $false
    }

    $reservados = @{
        21   = "FTP"
        22   = "SSH"
        25   = "SMTP"
        53   = "DNS"
        443  = "HTTPS"
        3306 = "MySQL"
        3389 = "RDP"
        5432 = "PostgreSQL"
    }

    if ($reservados.ContainsKey($n)) {
        Write-LogWar "Puerto $n reservado para $($reservados[$n])."
        return $false
    }

    $enUso = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
             Where-Object { $_.LocalPort -eq $n }

    if ($enUso) {
        Write-LogWar "Puerto $n ya esta en uso."
        return $false
    }

    return $true
}

# --------------------------------------------------------------
# PEDIR PUERTO CON VALIDACION
# (equivalente a ask_port en Linux)
# --------------------------------------------------------------
function Read-Port {
    param([string]$Prompt = "Puerto")

    while ($true) {
        $raw = Read-Host "  $Prompt (ej: 80, 8080, 8888)"
        $raw = $raw -replace '[^\d]', ''

        if ([string]::IsNullOrWhiteSpace($raw)) {
            Write-LogWar "No puede estar vacio."
            continue
        }

        if (Test-PortAvailable $raw) {
            Write-LogOK "Puerto $raw disponible."
            return [int]$raw
        }
    }
}

# --------------------------------------------------------------
# OBTENER VERSIONES DINAMICAS VIA CHOCOLATEY
# (equivalente a get_versions + select_version en Linux)
# --------------------------------------------------------------
function Get-ChocoVersions {
    param([string]$Package)

    Write-LogInf "Consultando versiones de $Package en Chocolatey..."

    try {
        $raw = choco search $Package --exact --all-versions 2>&1 |
               Where-Object { $_ -match "^\S" -and $_ -notmatch "^Chocolatey" -and $_ -notmatch "^\d+ packages" } |
               ForEach-Object { ($_ -split '\s+')[1] } |
               Where-Object { $_ -match '^\d' } |
               Select-Object -Unique

        # Ordenar descendente por version
        $sorted = $raw | Sort-Object {
            try { [version]($_ -replace '[^\d\.]','') } catch { [version]"0.0" }
        } -Descending | Select-Object -First 8

        return @($sorted)
    } catch {
        return @()
    }
}

function Select-Version {
    param([string]$Package)

    $versions = Get-ChocoVersions $Package

    if ($versions.Count -eq 0) {
        Write-LogWar "No se encontraron versiones. Se usara la ultima disponible."
        return "latest"
    }

    Write-Host ""
    Write-Host "  Versiones disponibles para ${Package}:"

    for ($i = 0; $i -lt $versions.Count; $i++) {
        $label = ""
        if ($i -eq 0)                   { $label = "  <- Mas reciente" }
        if ($i -eq $versions.Count - 1) { $label = "  <- LTS/Estable"  }
        Write-Host ("  {0,2}) {1}{2}" -f ($i + 1), $versions[$i], $label)
    }

    Write-Host ""

    while ($true) {
        $sel = Read-Host "  Seleccione version [1-$($versions.Count)]"
        $sel = $sel -replace '[^\d]', ''

        if ($sel -match '^\d+$') {
            $n = [int]$sel
            if ($n -ge 1 -and $n -le $versions.Count) {
                Write-LogOK "Version seleccionada: $($versions[$n - 1])"
                return $versions[$n - 1]
            }
        }
        Write-LogWar "Opcion invalida. Ingresa un numero entre 1 y $($versions.Count)."
    }
}

# --------------------------------------------------------------
# INDEX.HTML PERSONALIZADO
# (equivalente a create_index en Linux)
# --------------------------------------------------------------
function New-IndexHtml {
    param(
        [string]$Name,
        [string]$Version,
        [int]$Port,
        [string]$Root
    )

    if (-not (Test-Path $Root)) {
        New-Item -ItemType Directory -Path $Root -Force | Out-Null
    }

    $html = @"
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>$Name</title></head>
<body>
<h1>Servidor: $Name</h1>
<p>Version: $Version</p>
<p>Puerto: $Port</p>
<p>Aprovisionado via SSH</p>
</body>
</html>
"@

    Set-Content -Path "$Root\index.html" -Value $html -Encoding UTF8
    Write-LogOK "index.html creado en $Root"
}

# --------------------------------------------------------------
# HARDENING IIS
# (equivalente a harden_apache en Linux)
# --------------------------------------------------------------
function Invoke-HardenIIS {
    param([string]$SiteName = "Default Web Site")

    Write-LogInf "Aplicando hardening IIS..."
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Eliminar X-Powered-By
    try {
        Remove-WebConfigurationProperty `
            -PSPath "IIS:\Sites\$SiteName" `
            -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." `
            -AtElement @{name="X-Powered-By"} `
            -ErrorAction SilentlyContinue
        Write-LogOK "Header X-Powered-By eliminado"
    } catch { Write-LogWar "X-Powered-By ya no existia" }

    # Agregar headers de seguridad (sin duplicar)
    $headers = @(
        @{ name="X-Frame-Options";        value="SAMEORIGIN"    },
        @{ name="X-Content-Type-Options"; value="nosniff"       },
        @{ name="X-XSS-Protection";       value="1; mode=block" }
    )

    foreach ($h in $headers) {
        try {
            Remove-WebConfigurationProperty `
                -PSPath "IIS:\Sites\$SiteName" `
                -Filter "system.webServer/httpProtocol/customHeaders" `
                -Name "." -AtElement @{name=$h.name} -ErrorAction SilentlyContinue

            Add-WebConfigurationProperty `
                -PSPath "IIS:\Sites\$SiteName" `
                -Filter "system.webServer/httpProtocol/customHeaders" `
                -Name "." -Value $h
            Write-LogOK "Header $($h.name) configurado"
        } catch { Write-LogWar "Header $($h.name): $($_.Exception.Message)" }
    }

    # Ocultar version IIS (removeServerHeader)
    try {
        Set-WebConfigurationProperty `
            -PSPath "IIS:\" `
            -Filter "system.webServer/security/requestFiltering" `
            -Name "removeServerHeader" -Value $true -ErrorAction SilentlyContinue
        Write-LogOK "Header Server ocultado"
    } catch { Write-LogWar "removeServerHeader: $($_.Exception.Message)" }

    # Bloquear metodos peligrosos
    foreach ($method in @("TRACE","TRACK","DELETE","PUT","OPTIONS")) {
        try {
            Add-WebConfigurationProperty `
                -PSPath "IIS:\Sites\$SiteName" `
                -Filter "system.webServer/security/requestFiltering/verbs" `
                -Name "." -Value @{ verb=$method; allowed=$false } `
                -ErrorAction SilentlyContinue
        } catch { }
    }
    Write-LogOK "Metodos peligrosos bloqueados"
    Write-LogOK "Hardening IIS aplicado"
}

# --------------------------------------------------------------
# HARDENING APACHE WINDOWS
# --------------------------------------------------------------
function Invoke-HardenApacheWin {
    param([string]$ApacheBase)

    Write-LogInf "Aplicando hardening Apache Windows..."

    $httpdConf = "$ApacheBase\conf\httpd.conf"
    if (-not (Test-Path $httpdConf)) {
        Write-LogWar "httpd.conf no encontrado en $ApacheBase\conf"
        return
    }

    $c = Get-Content $httpdConf -Raw

    # ServerTokens
    if ($c -match 'ServerTokens')   { $c = $c -replace 'ServerTokens\s+\S+',   'ServerTokens Prod'  }
    else                            { $c += "`nServerTokens Prod"                                    }

    # ServerSignature
    if ($c -match 'ServerSignature') { $c = $c -replace 'ServerSignature\s+\S+', 'ServerSignature Off' }
    else                             { $c += "`nServerSignature Off"                                    }

    # TraceEnable
    if ($c -match 'TraceEnable')    { $c = $c -replace 'TraceEnable\s+\S+',    'TraceEnable Off'    }
    else                            { $c += "`nTraceEnable Off"                                      }

    Set-Content -Path $httpdConf -Value $c -Encoding UTF8

    # Archivo de seguridad extra
    $extraDir = "$ApacheBase\conf\extra"
    if (-not (Test-Path $extraDir)) { New-Item -ItemType Directory -Path $extraDir -Force | Out-Null }

    $secConf = @"
# Security Headers
<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
    Header always set X-XSS-Protection "1; mode=block"
    Header unset Server
    Header always unset X-Powered-By
</IfModule>

# Bloquear metodos peligrosos
<Directory "/">
    <LimitExcept GET POST HEAD>
        Require all denied
    </LimitExcept>
</Directory>
"@
    Set-Content -Path "$extraDir\seguridad.conf" -Value $secConf -Encoding UTF8

    # Incluir en httpd.conf
    $c2 = Get-Content $httpdConf -Raw
    if ($c2 -notmatch 'seguridad\.conf') {
        Add-Content -Path $httpdConf -Value "`nInclude conf/extra/seguridad.conf" -Encoding UTF8
    }

    Write-LogOK "Hardening Apache Windows aplicado"
}

# --------------------------------------------------------------
# HARDENING NGINX WINDOWS
# --------------------------------------------------------------
function Invoke-HardenNginxWin {
    param([string]$NginxBase)
    # El hardening de Nginx en Windows ya se inyecta directamente
    # en la conf que se reescribe en Deploy-NginxWin.
    # Esta funcion existe por modularidad y para futuras extensiones.
    Write-LogOK "Hardening Nginx incluido en nginx.conf"
}

# --------------------------------------------------------------
# VERIFICAR INSTALACION EXISTENTE
# (equivalente a check_existing en Linux)
# --------------------------------------------------------------
function Get-ExistingInstall {
    param([string]$Service)

    switch ($Service) {
        "iis" {
            $f = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
            if ($f -and $f.Installed) {
                $ver = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).VersionString
                if ($ver) { return "IIS $ver" } else { return "IIS instalado" }
            }
        }
        "apache" {
            $pkg = choco list --local-only 2>&1 | Where-Object { $_ -match '^apache' }
            if ($pkg) { return $pkg | Select-Object -First 1 }
            if (Test-Path "C:\Apache24\bin\httpd.exe") { return "Apache24 (directorio existente)" }
        }
        "nginx" {
            $pkg = choco list --local-only 2>&1 | Where-Object { $_ -match '^nginx' }
            if ($pkg) { return $pkg | Select-Object -First 1 }
            $base = Find-NginxBase
            if ($base) { return "Nginx (directorio existente: $base)" }
        }
    }
    return $null
}

# --------------------------------------------------------------
# PURGAR SERVICIO
# (equivalente a purge_service en Linux)
# --------------------------------------------------------------
function Remove-HttpService {
    param([string]$Service)

    Write-LogWar "Purgando $Service por completo..."

    switch ($Service) {
        "iis" {
            Import-Module WebAdministration -ErrorAction SilentlyContinue
            Get-Website   | Stop-Website    -ErrorAction SilentlyContinue
            # Desinstalar roles IIS
            $features = @("Web-Server","Web-WebServer","Web-Common-Http","Web-Default-Doc",
                          "Web-Static-Content","Web-Http-Errors","Web-Http-Logging",
                          "Web-Request-Monitor","Web-Filtering","Web-Stat-Compression",
                          "Web-Mgmt-Console","Web-Mgmt-Tools")
            foreach ($f in $features) {
                Remove-WindowsFeature -Name $f -ErrorAction SilentlyContinue | Out-Null
            }
            Remove-Item "C:\inetpub" -Recurse -Force -ErrorAction SilentlyContinue
            Write-LogOK "IIS purgado"
        }
        "apache" {
            # Detener y eliminar servicio
            $svc = Get-Service -Name "Apache*" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($svc) {
                Stop-Service $svc.Name -Force -ErrorAction SilentlyContinue
                $httpdExe = "C:\Apache24\bin\httpd.exe"
                if (Test-Path $httpdExe) { & $httpdExe -k uninstall -n $svc.Name 2>&1 | Out-Null }
                sc.exe delete $svc.Name 2>&1 | Out-Null
            }
            choco uninstall apache-httpd --force -y 2>&1 | Select-Object -Last 5
            Remove-Item "C:\Apache24"  -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item "C:\tools\Apache*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-LogOK "Apache Windows purgado"
        }
        "nginx" {
            Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force
            $svc = Get-Service -Name "nginx" -ErrorAction SilentlyContinue
            if ($svc) {
                Stop-Service "nginx" -Force -ErrorAction SilentlyContinue
                sc.exe delete nginx 2>&1 | Out-Null
            }
            choco uninstall nginx --force -y 2>&1 | Select-Object -Last 5
            choco uninstall nssm  --force -y 2>&1 | Out-Null
            $base = Find-NginxBase
            if ($base) { Remove-Item $base -Recurse -Force -ErrorAction SilentlyContinue }
            Remove-Item "C:\tools\nginx*" -Recurse -Force -ErrorAction SilentlyContinue
            Remove-Item "C:\nginx"        -Recurse -Force -ErrorAction SilentlyContinue
            Write-LogOK "Nginx Windows purgado"
        }
    }
}

# --------------------------------------------------------------
# PREGUNTAR REINSTALACION
# (equivalente a ask_reinstall en Linux)
# --------------------------------------------------------------
function Confirm-Reinstall {
    param([string]$Svc, [string]$VerExistente)

    Write-Host ""
    Write-LogWar "Ya existe $Svc instalado -> $VerExistente"
    Write-LogWar "Reinstalar borrara todo rastro anterior (recomendado para evitar corrupcion)."
    Write-Host ""

    while ($true) {
        $resp = (Read-Host "  Reinstalar? [s/N]") -replace '[^a-zA-Z]',''
        switch ($resp.ToLower()) {
            { $_ -in 's','si','y','yes' } { return $true  }
            { $_ -in 'n','no',''        } { return $false }
            default { Write-LogWar "Responde s o n." }
        }
    }
}

# --------------------------------------------------------------
# ABRIR PUERTO EN FIREWALL WINDOWS
# (equivalente a ufw allow $PORT/tcp en Linux)
# --------------------------------------------------------------
function Open-FirewallPort {
    param([int]$Port, [string]$Service)

    $ruleName = "HTTP-Prov-$Service-$Port"
    Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction   Inbound `
        -Protocol    TCP `
        -LocalPort   $Port `
        -Action      Allow `
        -Profile     Any `
        -ErrorAction Stop | Out-Null

    Write-LogOK "Puerto $Port abierto en Windows Firewall (regla: $ruleName)"
}

# --------------------------------------------------------------
# VERIFICAR SERVICIO ACTIVO
# (equivalente a check_service en Linux)
# --------------------------------------------------------------
function Wait-ServiceStart {
    param([string]$ServiceName, [int]$Port, [int]$MaxTries = 10)

    for ($i = 1; $i -le $MaxTries; $i++) {
        $listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
                     Where-Object { $_.LocalPort -eq $Port }

        $svcOk = $false
        $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($svc -and $svc.Status -eq 'Running') { $svcOk = $true }

        if ($listening -or $svcOk) {
            Write-LogOK "$ServiceName activo en puerto $Port"
            return $true
        }

        Write-LogInf "Esperando inicio de $ServiceName... ($i/$MaxTries)"
        Start-Sleep -Seconds 3
    }

    Write-LogErr "$ServiceName no inicio en el tiempo esperado."
    return $false
}

# --------------------------------------------------------------
# BUSCAR RUTA DE NGINX INSTALADO POR CHOCO
# --------------------------------------------------------------
function Find-NginxBase {
    $candidates = @(
        "C:\tools\nginx",
        "C:\ProgramData\chocolatey\lib\nginx\tools\nginx",
        "C:\nginx"
    )
    foreach ($c in $candidates) {
        if (Test-Path "$c\nginx.exe") { return $c }
    }
    $exe = Get-Command nginx.exe -ErrorAction SilentlyContinue
    if ($exe) { return Split-Path $exe.Source }
    return $null
}

# --------------------------------------------------------------
# BUSCAR RUTA DE APACHE INSTALADO POR CHOCO
# --------------------------------------------------------------
function Find-ApacheBase {
    $candidates = @(
        "C:\Apache24",
        "C:\tools\Apache24",
        "C:\ProgramData\chocolatey\lib\apache-httpd\tools\Apache24"
    )
    foreach ($c in $candidates) {
        if (Test-Path "$c\bin\httpd.exe") { return $c }
    }
    $exe = Get-Command httpd.exe -ErrorAction SilentlyContinue
    if ($exe) { return Split-Path (Split-Path $exe.Source) }
    return $null
}

# ==============================================================
# DEPLOY IIS  (obligatorio segun rubrica)
# ==============================================================
function Deploy-IIS {
    Write-Host ""
    Write-Log "=== DESPLIEGUE DE IIS ==="

    # 1. Verificar existente
    $verExistente = Get-ExistingInstall "iis"
    if ($verExistente) {
        if (Confirm-Reinstall "IIS" $verExistente) {
            Remove-HttpService "iis"
        } else {
            Write-LogInf "Omitiendo purge. Continuando con la configuracion..."
        }
    }

    # 2. IIS viene con Windows Server, no se elige version en choco
    Write-Host ""
    $winVer = (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
    Write-Host "  IIS se instala desde roles de Windows Server."
    Write-Host "  SO detectado: $winVer"
    Write-Host ""

    # 3. Puerto
    $port = Read-Port "Puerto de escucha para IIS"

    # 4. Instalar rol IIS
    Write-LogInf "Instalando rol IIS..."
    $features = @(
        "Web-Server","Web-WebServer","Web-Common-Http","Web-Default-Doc",
        "Web-Static-Content","Web-Http-Errors","Web-Http-Logging",
        "Web-Request-Monitor","Web-Filtering","Web-Stat-Compression",
        "Web-Mgmt-Console","Web-Mgmt-Tools"
    )
    foreach ($f in $features) {
        Install-WindowsFeature -Name $f -ErrorAction SilentlyContinue | Out-Null
    }

    Import-Module WebAdministration -ErrorAction Stop

    # 5. Configurar puerto
    Write-LogInf "Configurando IIS en puerto $port..."

    $siteName = "Default Web Site"
    $wwwroot   = "C:\inetpub\wwwroot"

    $site = Get-Website -Name $siteName -ErrorAction SilentlyContinue
    if (-not $site) {
        New-Item -ItemType Directory -Path $wwwroot -Force | Out-Null
        New-Website -Name $siteName -Port $port -PhysicalPath $wwwroot -Force | Out-Null
    } else {
        Remove-WebBinding -Name $siteName -ErrorAction SilentlyContinue
        New-WebBinding    -Name $siteName -Protocol "http" -Port $port -IPAddress "*" | Out-Null
    }

    # 6. Permisos NTFS en wwwroot
    New-Item -ItemType Directory -Path $wwwroot -Force | Out-Null
    $acl  = Get-Acl $wwwroot
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "IIS_IUSRS","ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")
    $acl.SetAccessRule($rule)
    Set-Acl -Path $wwwroot -AclObject $acl
    Write-LogOK "Permisos NTFS: IIS_IUSRS -> ReadAndExecute en $wwwroot"

    # 7. Version real
    $iisVer = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).VersionString
    if (-not $iisVer) { $iisVer = "10.x" }

    # 8. Index
    New-IndexHtml -Name "IIS" -Version $iisVer -Port $port -Root $wwwroot

    # 9. Hardening
    Invoke-HardenIIS -SiteName $siteName

    # 10. Iniciar
    Start-Service W3SVC -ErrorAction SilentlyContinue
    Start-Website -Name $siteName -ErrorAction SilentlyContinue
    iisreset /restart 2>&1 | Select-Object -Last 3

    # 11. Firewall
    Open-FirewallPort -Port $port -Service "IIS"

    # 12. Verificar
    Start-Sleep -Seconds 4
    if (Wait-ServiceStart -ServiceName "W3SVC" -Port $port) {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
               Where-Object { $_.InterfaceAlias -notmatch 'Loopback' } |
               Select-Object -First 1).IPAddress
        Write-Host ""
        Write-LogOK "IIS $iisVer activo en http://${ip}:${port}"
        Write-LogOK "Prueba: curl -I http://${ip}:${port}"
    } else {
        Write-LogErr "IIS no inicio. Revisa el Visor de Eventos de Windows."
    }
}


# --------------------------------------------------------------
# INSTALAR PAQUETE CHOCO CON LIMPIEZA DE RESIDUOS Y VERIFICACION
# Evita el "queda esperando y regresa sin error" de choco install
# --------------------------------------------------------------
function Install-ChocoPackage {
    param(
        [string]$Package,
        [string]$Version = "latest"
    )

    Write-LogInf "Preparando instalacion de $Package..."

    # Limpiar residuos de instalaciones anteriores de este paquete
    $pkgLibDir  = "C:\ProgramData\chocolatey\lib\$Package"
    $pkgBadDir  = "C:\ProgramData\chocolatey\lib-bad\$Package"
    $pkgTmpDir  = "C:\ProgramData\chocolatey\lib-bkp\$Package"

    foreach ($d in @($pkgBadDir, $pkgTmpDir)) {
        if (Test-Path $d) {
            Write-LogWar "Residuo choco encontrado: $d  -> eliminando"
            Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Si hay un lib dir pero el paquete no funciona, borrarlo
    if (Test-Path $pkgLibDir) {
        $verFile = "$pkgLibDir\$Package.nuspec"
        if (-not (Test-Path $verFile)) {
            Write-LogWar "Directorio de paquete incompleto: $pkgLibDir -> eliminando"
            Remove-Item $pkgLibDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    # Armar argumentos
    $chocoArgs = @("install", $Package, "--force", "-y", "--no-progress")
    if ($Version -ne "latest") {
        $chocoArgs += "--version=$Version"
    }

    Write-LogInf "Ejecutando: choco $($chocoArgs -join ' ')"

    # Ejecutar choco y capturar salida completa (visible + guardada en log)
    $output = & choco @chocoArgs 2>&1
    $exitCode = $LASTEXITCODE

    # Mostrar TODA la salida para que se vea en pantalla
    $output | ForEach-Object { Write-Host $_ }

    # Guardar en log
    $output | ForEach-Object { Add-Content -Path $LOG -Value $_ -Encoding UTF8 -ErrorAction SilentlyContinue }

    if ($exitCode -ne 0) {
        Write-LogErr "choco install $Package fallo con ExitCode $exitCode"
        Write-LogErr "Revisa el log completo en: $LOG"
        return $false
    }

    # Recargar PATH para que el binario recien instalado sea visible
    Refresh-EnvPath

    Write-LogOK "$Package instalado correctamente via Chocolatey"
    return $true
}

# ==============================================================
# DEPLOY APACHE WINDOWS  (opcion adicional via Chocolatey)
# ==============================================================
function Deploy-ApacheWin {
    Write-Host ""
    Write-Log "=== DESPLIEGUE DE APACHE (WINDOWS) ==="

    # 1. Verificar instalacion existente
    $verExistente = Get-ExistingInstall "apache"
    if ($verExistente) {
        if (Confirm-Reinstall "Apache" $verExistente) {
            Remove-HttpService "apache"
        } else {
            Write-LogInf "Omitiendo purge. Continuando con la configuracion..."
        }
    }

    # 2. Version dinamica via Chocolatey
    $version = Select-Version "apache-httpd"

    # 3. Puerto
    $port = Read-Port "Puerto de escucha para Apache"

    # 4. Instalar con funcion robusta (muestra errores, verifica exit code)
    Write-LogInf "Instalando Apache via Chocolatey..."
    $ok = Install-ChocoPackage -Package "apache-httpd" -Version $version
    if (-not $ok) {
        Write-LogErr "Instalacion de Apache fallo. Abortando."
        Write-LogErr "Puedes intentar manualmente: choco install apache-httpd --force -y"
        Read-Host "  Presiona Enter para volver al menu"
        return
    }

    # 5. Localizar directorio de Apache
    $apacheBase = Find-ApacheBase
    if (-not $apacheBase) {
        Write-LogErr "Apache instalado pero no encontrado en rutas conocidas."
        Write-LogErr "Rutas buscadas: C:\Apache24, C:\tools\Apache24"
        Write-LogErr "Revisa: $LOG"
        Read-Host "  Presiona Enter para volver al menu"
        return
    }
    Write-LogOK "Apache encontrado en: $apacheBase"

    # 6. Version real del binario
    $verReal = ""
    try {
        $verOut = & "$apacheBase\bin\httpd.exe" -v 2>&1
        $verLine = $verOut | Select-String "Server version"
        if ($verLine) {
            $verReal = ($verLine -split '/')[1] -split '\s' | Select-Object -First 1
        }
    } catch { }
    if (-not $verReal) { $verReal = $version }
    Write-LogOK "Version Apache: $verReal"

    # 7. Configurar puerto en httpd.conf
    Write-LogInf "Configurando Apache en puerto $port..."
    $httpdConf = "$apacheBase\conf\httpd.conf"

    if (-not (Test-Path $httpdConf)) {
        Write-LogErr "httpd.conf no encontrado en $apacheBase\conf"
        Read-Host "  Presiona Enter para volver al menu"
        return
    }

    $c = Get-Content $httpdConf -Raw

    # Reemplazar Listen
    if ($c -match 'Listen\s+\d+') {
        $c = $c -replace 'Listen\s+\d+', "Listen $port"
    } else {
        $c += "`nListen $port"
    }

    # Ajustar ServerRoot a ruta real de instalacion
    $apacheBaseEscaped = $apacheBase -replace '\\', '/'
    if ($c -match 'ServerRoot\s+"[^"]+"') {
        $c = $c -replace 'ServerRoot\s+"[^"]+"', "ServerRoot `"$apacheBaseEscaped`""
    }

    Set-Content -Path $httpdConf -Value $c -Encoding UTF8
    Write-LogOK "Puerto $port configurado en httpd.conf"

    # 8. DocumentRoot y permisos NTFS
    $docRoot = "$apacheBase\htdocs"
    New-Item -ItemType Directory -Path $docRoot -Force | Out-Null

    # Usuario dedicado con permisos limitados a htdocs
    $apacheUser = "ApacheSvc"
    if (-not (Get-LocalUser -Name $apacheUser -ErrorAction SilentlyContinue)) {
        try {
            Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
            $pw = [System.Web.Security.Membership]::GeneratePassword(16,2)
        } catch {
            $pw = "Apache@$(Get-Random -Minimum 10000 -Maximum 99999)!"
        }
        $secPw = ConvertTo-SecureString $pw -AsPlainText -Force
        New-LocalUser -Name $apacheUser -Password $secPw `
                      -PasswordNeverExpires -UserMayNotChangePassword `
                      -Description "Usuario dedicado Apache HTTP" `
                      -ErrorAction SilentlyContinue | Out-Null
        Write-LogOK "Usuario $apacheUser creado"
    }

    try {
        $acl  = Get-Acl $docRoot
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $apacheUser,"ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")
        $acl.SetAccessRule($rule)
        Set-Acl -Path $docRoot -AclObject $acl
        Write-LogOK "Permisos NTFS: $apacheUser -> ReadAndExecute en $docRoot"
    } catch {
        Write-LogWar "No se pudieron aplicar permisos NTFS: $_"
    }

    # 9. Index personalizado
    New-IndexHtml -Name "Apache" -Version $verReal -Port $port -Root $docRoot

    # 10. Hardening
    Invoke-HardenApacheWin -ApacheBase $apacheBase

    # 11. Registrar como servicio Windows e iniciar
    Write-LogInf "Registrando Apache como servicio Windows..."
    $regOut = & "$apacheBase\bin\httpd.exe" -k install -n "Apache" 2>&1
    $regOut | ForEach-Object { Write-Host $_ }

    Start-Service "Apache" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # Verificar que el servicio inicio
    $svc = Get-Service -Name "Apache" -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne 'Running') {
        Write-LogWar "Servicio Apache no inicio automaticamente. Intentando arranque directo..."
        $startOut = & "$apacheBase\bin\httpd.exe" -k start 2>&1
        $startOut | ForEach-Object { Write-Host $_ }
        Start-Sleep -Seconds 3
    }

    # 12. Firewall
    Open-FirewallPort -Port $port -Service "Apache"

    # 13. Verificar final
    if (Wait-ServiceStart -ServiceName "Apache" -Port $port) {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
               Where-Object { $_.InterfaceAlias -notmatch 'Loopback' } |
               Select-Object -First 1).IPAddress
        Write-Host ""
        Write-LogOK "Apache $verReal activo en http://${ip}:${port}"
        Write-LogOK "Prueba: curl -I http://${ip}:${port}"
    } else {
        Write-LogErr "Apache no inicio correctamente."
        Write-LogErr "Diagnostico:"
        & "$apacheBase\bin\httpd.exe" -t 2>&1 | ForEach-Object { Write-Host "  $_" }
        Write-LogErr "Log completo en: $LOG"
    }
}

# ==============================================================
# DEPLOY NGINX WINDOWS  (opcion adicional via Chocolatey)
# ==============================================================
function Deploy-NginxWin {
    Write-Host ""
    Write-Log "=== DESPLIEGUE DE NGINX (WINDOWS) ==="

    # 1. Verificar instalacion existente
    $verExistente = Get-ExistingInstall "nginx"
    if ($verExistente) {
        if (Confirm-Reinstall "Nginx" $verExistente) {
            Remove-HttpService "nginx"
        } else {
            Write-LogInf "Omitiendo purge. Continuando con la configuracion..."
        }
    }

    # 2. Version dinamica via Chocolatey
    $version = Select-Version "nginx"

    # 3. Puerto
    $port = Read-Port "Puerto de escucha para Nginx"

    # 4. Instalar con funcion robusta
    Write-LogInf "Instalando Nginx via Chocolatey..."
    $ok = Install-ChocoPackage -Package "nginx" -Version $version
    if (-not $ok) {
        Write-LogErr "Instalacion de Nginx fallo. Abortando."
        Write-LogErr "Puedes intentar manualmente: choco install nginx --force -y"
        Read-Host "  Presiona Enter para volver al menu"
        return
    }

    # 5. Localizar directorio de Nginx
    $nginxBase = Find-NginxBase
    if (-not $nginxBase) {
        Write-LogErr "Nginx instalado pero no encontrado en rutas conocidas."
        Write-LogErr "Rutas buscadas: C:\tools\nginx, C:\ProgramData\chocolatey\lib\nginx\tools\nginx, C:\nginx"
        Write-LogErr "Revisa: $LOG"
        Read-Host "  Presiona Enter para volver al menu"
        return
    }
    Write-LogOK "Nginx encontrado en: $nginxBase"

    # 6. Version real
    $verReal = ""
    try {
        $verOut = & "$nginxBase\nginx.exe" -v 2>&1
        $verReal = ($verOut | ForEach-Object { ($_ -split '/') | Select-Object -Last 1 }) | Select-Object -First 1
        $verReal = $verReal.Trim()
    } catch { }
    if (-not $verReal) { $verReal = $version }
    Write-LogOK "Version Nginx: $verReal"

    # 7. Reescribir nginx.conf completo con puerto correcto
    Write-LogInf "Configurando Nginx en puerto $port..."
    $nginxConf = "$nginxBase\conf\nginx.conf"
    $wwwRoot   = "$nginxBase\html"

    $confContent = @"
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
    server_tokens off;

    server {
        listen       $port;
        server_name  _;

        root   html;
        index  index.html index.htm;

        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;

        if (`$request_method !~ ^(GET|POST|HEAD)`$ ) {
            return 405;
        }

        location / {
            try_files `$uri `$uri/ =404;
        }

        location ~ /\. {
            deny all;
        }
    }
}
"@
    Set-Content -Path $nginxConf -Value $confContent -Encoding UTF8
    Write-LogOK "nginx.conf escrito con puerto $port"

    # 8. Validar configuracion antes de arrancar
    Write-LogInf "Validando configuracion de Nginx..."
    $testOut = & "$nginxBase\nginx.exe" -t -c $nginxConf 2>&1
    $testOut | ForEach-Object { Write-Host "  $_" }
    if ($LASTEXITCODE -ne 0) {
        Write-LogErr "nginx.conf tiene errores de sintaxis. Abortando."
        Read-Host "  Presiona Enter para volver al menu"
        return
    }
    Write-LogOK "Configuracion Nginx valida"

    # 9. Permisos NTFS en html
    New-Item -ItemType Directory -Path $wwwRoot -Force | Out-Null

    $nginxUser = "NginxSvc"
    if (-not (Get-LocalUser -Name $nginxUser -ErrorAction SilentlyContinue)) {
        try {
            Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue
            $pw = [System.Web.Security.Membership]::GeneratePassword(16,2)
        } catch {
            $pw = "Nginx@$(Get-Random -Minimum 10000 -Maximum 99999)!"
        }
        $secPw = ConvertTo-SecureString $pw -AsPlainText -Force
        New-LocalUser -Name $nginxUser -Password $secPw `
                      -PasswordNeverExpires -UserMayNotChangePassword `
                      -Description "Usuario dedicado Nginx" `
                      -ErrorAction SilentlyContinue | Out-Null
        Write-LogOK "Usuario $nginxUser creado"
    }

    try {
        $acl  = Get-Acl $wwwRoot
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $nginxUser,"ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")
        $acl.SetAccessRule($rule)
        Set-Acl -Path $wwwRoot -AclObject $acl
        Write-LogOK "Permisos NTFS: $nginxUser -> ReadAndExecute en $wwwRoot"
    } catch {
        Write-LogWar "No se pudieron aplicar permisos NTFS: $_"
    }

    # 10. Index personalizado
    New-IndexHtml -Name "Nginx" -Version $verReal -Port $port -Root $wwwRoot

    # 11. Hardening (ya incluido en nginx.conf)
    Invoke-HardenNginxWin -NginxBase $nginxBase

    # 12. Registrar como servicio con NSSM
    Write-LogInf "Instalando NSSM para gestionar Nginx como servicio..."
    if (-not (Get-Command nssm -ErrorAction SilentlyContinue)) {
        $nssmOk = Install-ChocoPackage -Package "nssm" -Version "latest"
        if (-not $nssmOk) {
            Write-LogWar "NSSM no se instalo. Nginx correra como proceso en background."
        }
    } else {
        Write-LogOK "NSSM ya disponible"
    }

    # Quitar servicio nginx previo si existe
    $svcExiste = Get-Service -Name "nginx" -ErrorAction SilentlyContinue
    if ($svcExiste) {
        Write-LogInf "Eliminando servicio nginx previo..."
        Stop-Service "nginx" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (Get-Command nssm -ErrorAction SilentlyContinue) {
            nssm remove nginx confirm 2>&1 | Out-Null
        } else {
            sc.exe delete nginx 2>&1 | Out-Null
        }
        Start-Sleep -Seconds 2
    }

    # Matar cualquier proceso nginx colgado
    Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force

    if (Get-Command nssm -ErrorAction SilentlyContinue) {
        Write-LogInf "Registrando Nginx con NSSM..."
        $nssmOut = nssm install nginx "$nginxBase\nginx.exe" 2>&1
        $nssmOut | ForEach-Object { Write-Host "  $_" }
        nssm set nginx AppDirectory $nginxBase 2>&1 | Out-Null
        nssm set nginx AppStdout "$nginxBase\logs\nssm-stdout.log" 2>&1 | Out-Null
        nssm set nginx AppStderr "$nginxBase\logs\nssm-stderr.log" 2>&1 | Out-Null
        Start-Sleep -Seconds 1
        $startOut = nssm start nginx 2>&1
        $startOut | ForEach-Object { Write-Host "  $_" }
    } else {
        # Fallback: arrancar nginx directamente como proceso
        Write-LogWar "NSSM no disponible. Arrancando Nginx directamente..."
        Start-Process -FilePath "$nginxBase\nginx.exe" `
                      -WorkingDirectory $nginxBase `
                      -WindowStyle Hidden
    }

    Start-Sleep -Seconds 4

    # 13. Firewall
    Open-FirewallPort -Port $port -Service "Nginx"

    # 14. Verificar
    if (Wait-ServiceStart -ServiceName "nginx" -Port $port) {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
               Where-Object { $_.InterfaceAlias -notmatch 'Loopback' } |
               Select-Object -First 1).IPAddress
        Write-Host ""
        Write-LogOK "Nginx $verReal activo en http://${ip}:${port}"
        Write-LogOK "Prueba: curl -I http://${ip}:${port}"
    } else {
        Write-LogErr "Nginx no inicio correctamente."
        Write-LogErr "Diagnostico:"
        if (Test-Path "$nginxBase\logs\error.log") {
            Get-Content "$nginxBase\logs\error.log" -Tail 10 | ForEach-Object { Write-Host "  $_" }
        }
        if (Get-Command nssm -ErrorAction SilentlyContinue) {
            Write-LogErr "Estado NSSM: $(nssm status nginx 2>&1)"
        }
        Write-LogErr "Log completo en: $LOG"
    }
}