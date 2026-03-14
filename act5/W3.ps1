Import-Module WebAdministration

$FTP="C:\FTP"
$GENERAL="C:\FTP\LocalUser\Public\general"
$REPRO="C:\FTP\reprobados"
$RECUR="C:\FTP\recursadores"
$LOCALUSER="C:\FTP\LocalUser"

Write-Host "===================================="
Write-Host "REPARACION COMPLETA DEL SERVIDOR FTP"
Write-Host "===================================="

$rutas=@($FTP,$GENERAL,$REPRO,$RECUR,$LOCALUSER)
foreach($r in $rutas){
    if(!(Test-Path $r)){ Write-Host "Creando: $r"; New-Item $r -ItemType Directory -Force | Out-Null }
}

Write-Host "Aplicando permisos base..."
icacls $FTP /inheritance:r | Out-Null
icacls $FTP /grant "Administrators:(OI)(CI)F" | Out-Null
icacls $FTP /grant "SYSTEM:(OI)(CI)F" | Out-Null
icacls $FTP /grant "IIS_IUSRS:(OI)(CI)RX" | Out-Null

Write-Host "Permisos carpetas publicas y grupos..."
icacls $GENERAL /grant "ftpusers:(OI)(CI)M" | Out-Null
icacls $REPRO /grant "reprobados:(OI)(CI)M" | Out-Null
icacls $RECUR /grant "recursadores:(OI)(CI)M" | Out-Null

Write-Host "Permisos estructura usuarios..."
icacls $LOCALUSER /grant "ftpusers:(OI)(CI)RX" | Out-Null

Write-Host "Reconfigurando IIS FTP..."
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value 0

Clear-WebConfiguration -Filter system.ftpServer/security/authorization -PSPath "IIS:\Sites\FTP" -ErrorAction SilentlyContinue
Add-WebConfiguration -Filter system.ftpServer/security/authorization -PSPath "IIS:\Sites\FTP" -Value @{accessType="Allow";users="*";permissions="Read,Write"}

Restart-Service ftpsvc
Write-Host "PERMISOS REPARADOS CORRECTAMENTE" -ForegroundColor Green