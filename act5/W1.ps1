# =========================================================
# SCRIPT MAESTRO: INSTALACIÓN Y CONFIGURACIÓN FTP (IIS)
# =========================================================

Write-Host "--- 1. Instalando Características de Servidor ---" -ForegroundColor Cyan
# Primero instalamos, luego importamos el módulo
Install-WindowsFeature Web-Server, Web-Mgmt-Console, Web-FTP-Server, Web-FTP-Service, Web-FTP-Ext -IncludeManagementTools

# Importar módulos ahora que ya existen
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
$rutas = @(
    "C:\FTP\general",
    "C:\FTP\usuarios\reprobados",
    "C:\FTP\usuarios\recursadores",
    "C:\FTP\vhome\LocalUser"
)
foreach ($ruta in $rutas) {
    if (!(Test-Path $ruta)) {
        New-Item -Path $ruta -ItemType Directory -Force | Out-Null
        Write-Host "Carpeta creada: $ruta"
    }
}

Write-Host "--- 4. Aplicando Permisos Base (NTFS) ---" -ForegroundColor Cyan
# Reset de herencia y permisos de sistema
icacls "C:\FTP" /inheritance:r
icacls "C:\FTP" /grant "Administradores:(OI)(CI)F"
icacls "C:\FTP" /grant "SYSTEM:(OI)(CI)F"
icacls "C:\FTP" /grant "IIS_IUSRS:(OI)(CI)RX"

# Permisos para grupos específicos
# Nota: Usamos llaves si hubiera variables, aquí son nombres fijos
icacls "C:\FTP\general" /grant "ftpusers:(OI)(CI)M"
icacls "C:\FTP\usuarios\reprobados" /grant "reprobados:(OI)(CI)M"
icacls "C:\FTP\usuarios\recursadores" /grant "recursadores:(OI)(CI)M"

Write-Host "--- 5. Configurando Sitio FTP en IIS ---" -ForegroundColor Cyan
if (!(Test-Path "IIS:\Sites\FTP")) {
    New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath "C:\FTP" -Force
    Write-Host "Sitio FTP creado."
}

# Autenticación Básica y Anónima
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true

# Aislamiento de Usuarios (Modo 3: Directorio de nombre de usuario)
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.userIsolation.mode -Value 3

Write-Host "--- 6. Configurando Reglas de Autorización ---" -ForegroundColor Cyan
# Limpiar reglas viejas
Clear-WebConfiguration -Filter system.ftpServer/security/authorization -PSPath "IIS:\Sites\FTP"

# Permitir lectura a todos (Anónimo)
Add-WebConfiguration -Filter system.ftpServer/security/authorization -PSPath "IIS:\Sites\FTP" -Value @{accessType="Allow"; users="*"; permissions="Read"}

# Permitir lectura/escritura a miembros de ftpusers
Add-WebConfiguration -Filter system.ftpServer/security/authorization -PSPath "IIS:\Sites\FTP" -Value @{accessType="Allow"; roles="ftpusers"; permissions="Read,Write"}

Write-Host "--- 7. Finalizando ---" -ForegroundColor Cyan
Restart-Service ftpsvc
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  SERVIDOR FTP LISTO PARA RECIBIR USUARIOS" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green