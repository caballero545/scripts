Import-Module WebAdministration

$FTP="C:\FTP"
$GENERAL="$FTP\general"
$REPRO="$FTP\reprobados"
$RECUR="$FTP\recursadores"
$LOCALUSER="$FTP\LocalUser"

Write-Host "===================================="
Write-Host "REPARACION COMPLETA DEL SERVIDOR FTP"
Write-Host "===================================="

# verificar estructura
$rutas=@($FTP,$GENERAL,$REPRO,$RECUR,$LOCALUSER)

foreach($r in $rutas){

if(!(Test-Path $r)){
Write-Host "Creando carpeta faltante: $r"
New-Item $r -ItemType Directory | Out-Null
}

}

Write-Host "Aplicando permisos base..."

icacls $FTP /inheritance:r

icacls $FTP /grant "Administrators:(OI)(CI)F"
icacls $FTP /grant "SYSTEM:(OI)(CI)F"
icacls $FTP /grant "IIS_IUSRS:(OI)(CI)RX"
icacls $FTP /grant "Users:(RX)"

Write-Host "Permisos carpetas publicas"

icacls $GENERAL /grant "ftpusers:(OI)(CI)M"
icacls $REPRO /grant "reprobados:(OI)(CI)M"
icacls $RECUR /grant "recursadores:(OI)(CI)M"

Write-Host "Permisos estructura usuarios"

icacls $LOCALUSER /grant "Users:(RX)"
icacls $LOCALUSER /grant "ftpusers:(OI)(CI)RX"

Write-Host "Reconfigurando IIS FTP"

Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true

Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"

Clear-WebConfiguration -Filter system.ftpServer/security/authorization -PSPath "IIS:\Sites\FTP" -ErrorAction SilentlyContinue

Add-WebConfiguration -Filter system.ftpServer/security/authorization -PSPath "IIS:\Sites\FTP" -Value @{accessType="Allow";users="anonymous";permissions="Read"}

Add-WebConfiguration -Filter system.ftpServer/security/authorization -PSPath "IIS:\Sites\FTP" -Value @{accessType="Allow";roles="ftpusers";permissions="Read,Write"}

Write-Host "Reiniciando servicio FTP"

Restart-Service ftpsvc

Write-Host "===================================="
Write-Host "PERMISOS REPARADOS CORRECTAMENTE"
Write-Host "===================================="