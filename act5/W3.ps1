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

# tomar posesión
cmd /c "takeown /f $BASE /r /d y" | Out-Null
cmd /c "icacls $BASE /grant Administrators:(OI)(CI)F /T /C /Q" | Out-Null

# limpiar ACL
icacls $BASE /reset /T /C | Out-Null

# permisos base
icacls $BASE /inheritance:r | Out-Null
icacls $BASE /grant "Administrators:(OI)(CI)F" | Out-Null
icacls $BASE /grant "SYSTEM:(OI)(CI)F" | Out-Null
icacls $BASE /grant "IIS_IUSRS:(OI)(CI)RX" | Out-Null

# carpetas grupo
if(Test-Path $REPRO){
icacls $REPRO /grant "reprobados:(OI)(CI)M" | Out-Null
}

if(Test-Path $RECUR){
icacls $RECUR /grant "recursadores:(OI)(CI)M" | Out-Null
}

# carpeta pública
if(Test-Path $PUBLIC){
icacls $PUBLIC /grant "IUSR:(OI)(CI)RX" | Out-Null
}

if(Test-Path $GENERAL){
icacls $GENERAL /grant "ftpusers:(OI)(CI)M" | Out-Null
icacls $GENERAL /grant "IUSR:(OI)(CI)RX" | Out-Null
}

# reparar usuarios
$usuarios = Get-ChildItem $LOCAL -Directory -ErrorAction SilentlyContinue | Where{$_.Name -ne "Public"}

foreach($u in $usuarios){

$nombre=$u.Name
$home=$u.FullName

Write-Host "Reparando usuario $nombre" -ForegroundColor Yellow

icacls $home /inheritance:r | Out-Null
icacls $home /grant "$($nombre):(OI)(CI)M" | Out-Null
icacls $home /grant "Administrators:(OI)(CI)F" | Out-Null
icacls $home /grant "SYSTEM:(OI)(CI)F" | Out-Null

icacls $LOCAL /grant "$($nombre):(RX)" | Out-Null

}

# configurar IIS
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.userIsolation.mode -Value "IsolateAllDirectories"

Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value 0

Clear-WebConfiguration "/system.ftpServer/security/authorization" -PSPath IIS:\ -Location FTP

Add-WebConfiguration "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="?";permissions=1} -PSPath IIS:\ -Location FTP
Add-WebConfiguration "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="*";permissions=3} -PSPath IIS:\ -Location FTP

Restart-Service ftpsvc

Write-Host "======================================" -ForegroundColor Green
Write-Host " FTP REPARADO COMPLETAMENTE"
Write-Host "======================================" -ForegroundColor Green