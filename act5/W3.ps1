$FTP="C:\FTP"

Write-Host "--- 1. Limpiando archivos corruptos ---" -ForegroundColor Cyan
# ESTO SOLUCIONA EL ERROR DE DUPLICADOS: Borramos el web.config intruso
if (Test-Path "$FTP\web.config") {
    Remove-Item "$FTP\web.config" -Force
    Write-Host "Archivo web.config corrupto eliminado." -ForegroundColor Yellow
}

Write-Host "--- 2. Aplicando permisos NTFS base ---" -ForegroundColor Cyan
icacls $FTP /inheritance:r
icacls $FTP /grant "Administrators:(OI)(CI)F"
icacls $FTP /grant "SYSTEM:(OI)(CI)F"
icacls $FTP /grant "IIS_IUSRS:(OI)(CI)RX"
icacls $FTP /grant "Users:(RX)"

Write-Host "--- 3. Permisos de carpetas ---" -ForegroundColor Cyan
icacls "C:\FTP\general" /grant "ftpusers:(OI)(CI)M"
icacls "C:\FTP\usuarios\reprobados" /grant "reprobados:(OI)(CI)M"
icacls "C:\FTP\usuarios\recursadores" /grant "recursadores:(OI)(CI)M"

Write-Host "--- 4. Permisos vhome ---" -ForegroundColor Cyan
icacls "C:\FTP\vhome" /grant "Users:(RX)"
icacls "C:\FTP\vhome\LocalUser" /grant "Users:(RX)"
icacls "C:\FTP\vhome\LocalUser" /grant "ftpusers:(OI)(CI)RX"
icacls "C:\FTP\vhome" /grant "ftpusers:(RX)"

Import-Module WebAdministration

Write-Host "--- 5. Configurando Reglas de IIS y SSL ---" -ForegroundColor Cyan

# Asegurarnos de que la Autenticación Básica esté ACTIVA (Evita el Error 530)
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

# Limpiar autorizaciones usando la ruta correcta (IIS:\Sites\FTP)
Clear-WebConfiguration -Filter "system.ftpServer/security/authorization" -PSPath "IIS:\Sites\FTP"

# Agregar reglas correctamente sin usar -Location
Add-WebConfiguration -Filter "system.ftpServer/security/authorization" -PSPath "IIS:\Sites\FTP" -Value @{accessType="Allow";users="*";permissions="Read"}
Add-WebConfiguration -Filter "system.ftpServer/security/authorization" -PSPath "IIS:\Sites\FTP" -Value @{accessType="Allow";roles="ftpusers";permissions="Read,Write"}

# Configurar SSL correctamente usando Set-ItemProperty (Elimina los WARNINGS)
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"

# Reiniciar el servicio FTP
Restart-Service ftpsvc

Write-Host "==========================================" -ForegroundColor Green
Write-Host "  PERMISOS Y REGLAS APLICADOS CORRECTAMENTE" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green