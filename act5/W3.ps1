Import-Module WebAdministration

$FTP="C:\FTP"
$GENERAL="C:\FTP\LocalUser\Public\general"
$REPRO="C:\FTP\reprobados"
$RECUR="C:\FTP\recursadores"
$LOCALUSER="C:\FTP\LocalUser"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   REPARACION INTEGRAL DEL SERVIDOR FTP (MODO 3)" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# 1. Asegurar que las carpetas base existan
$rutas=@($FTP,$GENERAL,$REPRO,$RECUR,$LOCALUSER)
foreach($r in $rutas){
    if(!(Test-Path $r)){ 
        Write-Host "Creando carpeta faltante: $r" -ForegroundColor Yellow
        New-Item $r -ItemType Directory -Force | Out-Null 
    }
}

# 2. Aplicar permisos base al sistema
Write-Host "Aplicando permisos de herencia y sistema..." -ForegroundColor Gray
icacls $FTP /inheritance:r | Out-Null
icacls $FTP /grant "Administrators:(OI)(CI)F" | Out-Null
icacls $FTP /grant "SYSTEM:(OI)(CI)F" | Out-Null
icacls $FTP /grant "IIS_IUSRS:(OI)(CI)RX" | Out-Null

# 3. Permisos en carpetas de grupo y públicas
Write-Host "Configurando permisos de grupos..." -ForegroundColor Gray
icacls $GENERAL /grant "ftpusers:(OI)(CI)M" | Out-Null
icacls $REPRO /grant "reprobados:(OI)(CI)M" | Out-Null
icacls $RECUR /grant "recursadores:(OI)(CI)M" | Out-Null
icacls $LOCALUSER /grant "ftpusers:(OI)(CI)RX" | Out-Null

# 4. PARTE CRÍTICA: Reparación de cada usuario individualmente
# Esto es lo que arregla el Error 530 para usuarios ya creados
Write-Host "`n--- REPARANDO USUARIOS DENTRO DE LOCALUSER ---" -ForegroundColor Cyan
$carpetasUsuarios = Get-ChildItem $LOCALUSER -Directory | Where-Object { $_.Name -ne "Public" }

foreach ($folder in $carpetasUsuarios) {
    $u = $folder.Name
    $uPath = $folder.FullName
    Write-Host "Reparando: $u..." -ForegroundColor Yellow

    # Re-aplicar permisos NTFS al usuario (usando las llaves {} para evitar error de sintaxis)
    icacls $uPath /inheritance:r | Out-Null
    icacls $uPath /grant "Administradores:(OI)(CI)F" | Out-Null
    icacls $uPath /grant "${u}:(OI)(CI)M" | Out-Null

    # Reparar enlaces simbólicos internos (por si quedaron rotos)
    # 1. Enlace a General
    if (!(Test-Path "$uPath\general")) {
        cmd /c mklink /D "$uPath\general" "$GENERAL" | Out-Null
    }

    # 2. Enlace a su grupo (detectamos en qué grupo está)
    if (Get-LocalGroupMember reprobados -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $u }) {
        if (!(Test-Path "$uPath\reprobados")) { cmd /c mklink /D "$uPath\reprobados" "$REPRO" | Out-Null }
    }
    elseif (Get-LocalGroupMember recursadores -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $u }) {
        if (!(Test-Path "$uPath\recursadores")) { cmd /c mklink /D "$uPath\recursadores" "$RECUR" | Out-Null }
    }
}

# 5. Reconfiguración de IIS (Aseguramos Modo 3)
Write-Host "`nReconfigurando IIS FTP..." -ForegroundColor Gray
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.userIsolation.mode -Value 3
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value 0

# Limpiar y re-aplicar reglas de autorización
Clear-WebConfiguration -Filter system.ftpServer/security/authorization -PSPath "IIS:\Sites\FTP" -ErrorAction SilentlyContinue
Add-WebConfiguration -Filter system.ftpServer/security/authorization -PSPath "IIS:\Sites\FTP" -Value @{accessType="Allow";users="*";permissions="Read,Write"}

Restart-Service ftpsvc
Write-Host "`n¡SERVIDOR REPARADO AL 100%! Intenta entrar por FTP ahora." -ForegroundColor Green