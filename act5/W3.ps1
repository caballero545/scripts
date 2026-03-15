Import-Module WebAdministration

$BASE="C:\FTP"
$LOCAL="C:\FTP\LocalUser"
$PUBLIC="C:\FTP\LocalUser\Public"
$GENERAL="C:\FTP\LocalUser\Public\General"
$REPRO="C:\FTP\reprobados"
$RECUR="C:\FTP\recursadores"

Write-Host "======================================" -ForegroundColor Cyan
Write-Host " REPARACION TOTAL DE PERMISOS FTP"
Write-Host "======================================" -ForegroundColor Cyan

#---------------------------------------------------
# 1 TOMAR POSESION TOTAL DEL FTP
#---------------------------------------------------

Write-Host "Tomando control del sistema FTP..." -ForegroundColor Yellow

cmd /c "takeown /f $BASE /r /d y" | Out-Null
cmd /c "icacls $BASE /grant Administrators:(OI)(CI)F /T /C /Q" | Out-Null

#---------------------------------------------------
# 2 LIMPIAR ACL COMPLETAMENTE
#---------------------------------------------------

Write-Host "Limpiando permisos viejos..." -ForegroundColor Yellow

icacls $BASE /reset /T /C | Out-Null

#---------------------------------------------------
# 3 PERMISOS BASE DEL SERVIDOR
#---------------------------------------------------

Write-Host "Aplicando permisos base..." -ForegroundColor Cyan

icacls $BASE /inheritance:r | Out-Null

icacls $BASE /grant "Administrators:(OI)(CI)F" | Out-Null
icacls $BASE /grant "SYSTEM:(OI)(CI)F" | Out-Null
icacls $BASE /grant "IIS_IUSRS:(OI)(CI)RX" | Out-Null

#---------------------------------------------------
# 4 PERMISOS CARPETAS PRINCIPALES
#---------------------------------------------------

Write-Host "Configurando carpetas FTP..." -ForegroundColor Cyan

icacls $REPRO /grant "reprobados:(OI)(CI)M" | Out-Null
icacls $RECUR /grant "recursadores:(OI)(CI)M" | Out-Null

icacls $PUBLIC /grant "IUSR:(OI)(CI)RX" | Out-Null
icacls $GENERAL /grant "ftpusers:(OI)(CI)M" | Out-Null
icacls $GENERAL /grant "IUSR:(OI)(CI)RX" | Out-Null

#---------------------------------------------------
# 5 REPARAR USUARIOS FTP
#---------------------------------------------------

Write-Host "Reparando usuarios..." -ForegroundColor Cyan

$usuarios = Get-ChildItem $LOCAL -Directory | Where{$_.Name -ne "Public"}

foreach($u in $usuarios){

$nombre=$u.Name
$home=$u.FullName

Write-Host "Reparando usuario $nombre" -ForegroundColor Yellow

# limpiar herencia
icacls $home /inheritance:r | Out-Null

# permisos home
icacls $home /grant "${nombre}:(OI)(CI)M" | Out-Null
icacls $home /grant "Administrators:(OI)(CI)F" | Out-Null
icacls $home /grant "SYSTEM:(OI)(CI)F" | Out-Null

# permiso atravesar LocalUser
icacls $LOCAL /grant "${nombre}:(RX)" | Out-Null

}

#---------------------------------------------------
# 6 ARREGLAR IIS FTP
#---------------------------------------------------

Write-Host "Reconfigurando IIS FTP..." -ForegroundColor Cyan

Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true

Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.userIsolation.mode -Value "IsolateAllDirectories"

Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value 0

Clear-WebConfiguration "/system.ftpServer/security/authorization" -PSPath IIS:\ -Location FTP

Add-WebConfiguration "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="?";permissions=1} -PSPath IIS:\ -Location FTP
Add-WebConfiguration "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="*";permissions=3} -PSPath IIS:\ -Location FTP

#---------------------------------------------------
# 7 REINICIAR FTP
#---------------------------------------------------

Write-Host "Reiniciando servicio FTP..." -ForegroundColor Cyan

Restart-Service ftpsvc

Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host " FTP REPARADO COMPLETAMENTE"
Write-Host "======================================" -ForegroundColor Green