Import-Module WebAdministration

$FTP="C:\FTP"
$GENERAL="C:\FTP\LocalUser\Public\general"
$REPRO="C:\FTP\reprobados"
$RECUR="C:\FTP\recursadores"
$LOCALUSER="C:\FTP\LocalUser"

Write-Host "====================================================" -ForegroundColor Cyan
Write-Host "   REPARACION FINAL Y LIMPIEZA DE PERMISOS" -ForegroundColor Cyan
Write-Host "====================================================" -ForegroundColor Cyan

# 1. Asegurar carpetas base
$rutas=@($FTP,$GENERAL,$REPRO,$RECUR,$LOCALUSER)
foreach($r in $rutas){
    if(!(Test-Path $r)){ New-Item $r -ItemType Directory -Force | Out-Null }
}

# 2. Permisos base usando SIDs (S-1-5-32-544 es el grupo Administrators)
Write-Host "Corrigiendo permisos raíz..." -ForegroundColor Gray
icacls $FTP /inheritance:e | Out-Null # Primero restauramos herencia para poder trabajar
icacls $FTP /grant "*S-1-5-32-544:(OI)(CI)F" /T /C /Q | Out-Null
icacls $FTP /grant "SYSTEM:(OI)(CI)F" /T /C /Q | Out-Null
icacls $FTP /grant "IIS_IUSRS:(OI)(CI)RX" /T /C /Q | Out-Null

# 3. Reparación de usuarios individuales
Write-Host "`n--- REPARANDO CARPETAS DE USUARIOS ---" -ForegroundColor Cyan
$carpetas = Get-ChildItem $LOCALUSER -Directory | Where-Object { $_.Name -ne "Public" }

foreach ($folder in $carpetas) {
    $u = $folder.Name
    $uPath = $folder.FullName
    Write-Host "Limpiando y reparando: $u..." -ForegroundColor Yellow

    # Otorgar control total al administrador y al usuario
    icacls $uPath /grant "*S-1-5-32-544:(OI)(CI)F" /Q | Out-Null
    icacls $uPath /grant "${u}:(OI)(CI)M" /Q | Out-Null

    # LIMPIEZA DE LINKS: Borrar si ya existen para evitar el error "File already exists"
    if (Test-Path "$uPath\general") { cmd /c rmdir "$uPath\general" 2>$null }
    if (Test-Path "$uPath\reprobados") { cmd /c rmdir "$uPath\reprobados" 2>$null }
    if (Test-Path "$uPath\recursadores") { cmd /c rmdir "$uPath\recursadores" 2>$null }

    # Crear enlaces nuevos
    cmd /c mklink /D "$uPath\general" "$GENERAL" | Out-Null
    
    if (Get-LocalGroupMember reprobados -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $u }) {
        cmd /c mklink /D "$uPath\reprobados" "$REPRO" | Out-Null
        Write-Host " -> Link a Reprobados creado." -ForegroundColor DarkGray
    }
    elseif (Get-LocalGroupMember recursadores -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $u }) {
        cmd /c mklink /D "$uPath\recursadores" "$RECUR" | Out-Null
        Write-Host " -> Link a Recursadores creado." -ForegroundColor DarkGray
    }
}

# 4. Forzar configuración de IIS
Write-Host "`nAplicando configuración de Aislamiento Modo 3..." -ForegroundColor Gray
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.userIsolation.mode -Value 3
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

# Limpiar reglas de autorización
Clear-WebConfiguration -Filter system.ftpServer/security/authorization -PSPath "IIS:\Sites\FTP" -ErrorAction SilentlyContinue
Add-WebConfiguration -Filter system.ftpServer/security/authorization -PSPath "IIS:\Sites\FTP" -Value @{accessType="Allow";users="*";permissions="Read,Write"}

Restart-Service ftpsvc
Write-Host "`n¡SISTEMA CURADO! Prueba entrar ahora." -ForegroundColor Green