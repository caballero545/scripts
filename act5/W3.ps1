Import-Module WebAdministration

$BASE="C:\FTP"
$LOCAL="C:\FTP\LocalUser"
$GENERAL="C:\FTP\LocalUser\Public\General"

Write-Host "Reparando permisos FTP..." -ForegroundColor Cyan

icacls $BASE /grant "Administrators:(OI)(CI)F" /T /C | Out-Null
icacls $BASE /grant "SYSTEM:(OI)(CI)F" /T /C | Out-Null
icacls $BASE /grant "IIS_IUSRS:(OI)(CI)RX" /T /C | Out-Null

icacls $GENERAL /grant "ftpusers:(OI)(CI)M" | Out-Null
icacls $GENERAL /grant "IUSR:(OI)(CI)RX" | Out-Null

$usuarios=Get-ChildItem $LOCAL -Directory | Where{$_.Name -ne "Public"}

foreach($u in $usuarios){

$nombre=$u.Name
$home=$u.FullName

Write-Host "Reparando $nombre"

icacls $home /grant "$nombre:(OI)(CI)M" | Out-Null
icacls $home /grant "Administrators:(OI)(CI)F" | Out-Null

icacls $LOCAL /grant "$nombre:(RX)" | Out-Null
}

Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.userIsolation.mode -Value "IsolateAllDirectories"

Restart-Service ftpsvc

Write-Host "Permisos reparados." -ForegroundColor Green