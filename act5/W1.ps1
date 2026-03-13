# =========================================================
# SCRIPT MAESTRO V2: INSTALACIÓN + DESBLOQUEO + CONFIG
# =========================================================

Write-Host "--- 1. Instalando Características y Desbloqueando IIS ---" -ForegroundColor Cyan
Install-WindowsFeature Web-Server, Web-Mgmt-Console, Web-FTP-Server, Web-FTP-Service, Web-FTP-Ext -IncludeManagementTools

# ESTO ES LO QUE ARREGLA EL ERROR DE LA CAPTURA image_4f2cb5.png
# Desbloqueamos las secciones para que el script tenga permiso de escribir
$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
& $appcmd unlock config -section:system.ftpServer/security/authentication
& $appcmd unlock config -section:system.ftpServer/security/authorization

Import-Module WebAdministration

Write-Host "--- 2. Creando Grupos Locales ---" -ForegroundColor Cyan
$grupos = @("reprobados", "recursadores", "ftpusers")
foreach ($grupo in $grupos) {
    if (!(Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue)) {
        New-LocalGroup -Name $grupo
        Write-Host "Grupo $grupo creado."
    }
}

Write-Host "--- 3. Creando Estructura de Directorios ---" -ForegroundColor Cyan
$rutas = @("C:\FTP\general", "C:\FTP\usuarios\reprobados", "C:\FTP\usuarios\recursadores", "C:\FTP\vhome\LocalUser")
foreach ($ruta in $rutas) {
    if (!(Test-Path $ruta)) {
        New-Item -Path $ruta -ItemType Directory -Force | Out-Null
    }
}

Write-Host "--- 4. Aplicando Permisos Base (NTFS) ---" -ForegroundColor Cyan
icacls "C:\FTP" /inheritance:r
icacls "C:\FTP" /grant "Administradores:(OI)(CI)F"
icacls "C:\FTP" /grant "SYSTEM:(OI)(CI)F"
icacls "C:\FTP" /grant "IIS_IUSRS:(OI)(CI)RX"

# Aquí ya usamos el fix de llaves para evitar el error de image_50a639.png
icacls "C:\FTP\general" /grant "ftpusers:(OI)(CI)M"
icacls "C:\FTP\usuarios\reprobados" /grant "reprobados:(OI)(CI)M"
icacls "C:\FTP\usuarios\recursadores" /grant "recursadores:(OI)(CI)M"

Write-Host "--- 5. Configurando Sitio FTP ---" -ForegroundColor Cyan
if (!(Test-Path "IIS:\Sites\FTP")) {
    New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath "C:\FTP" -Force
}

Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.userIsolation.mode -Value 3

Write-Host "--- 6. Configurando Reglas de Autorización ---" -ForegroundColor Cyan
# Ahora que está desbloqueado, estos comandos ya no darán error
Clear-WebConfiguration -Filter system.ftpServer/security/authorization -PSPath "IIS:\Sites\FTP"
Add-WebConfiguration -Filter system.ftpServer/security/authorization -PSPath "IIS:\Sites\FTP" -Value @{accessType="Allow"; users="*"; permissions="Read"}
Add-WebConfiguration -Filter system.ftpServer/security/authorization -PSPath "IIS:\Sites\FTP" -Value @{accessType="Allow"; roles="ftpusers"; permissions="Read,Write"}

Restart-Service ftpsvc
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  ¡LISTO! SIN ERRORES DE BLOQUEO" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green