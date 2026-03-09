$FTP="C:\FTP"

Write-Host "===== ARREGLANDO PERMISOS FTP ====="

icacls $FTP /grant "Users:(RX)"

icacls "$FTP\general" /grant "ftpusers:(M)"

icacls "$FTP\usuarios\reprobados" /grant "reprobados:(M)"
icacls "$FTP\usuarios\recursadores" /grant "recursadores:(M)"

Get-ChildItem "$FTP\vhome" | ForEach-Object {

$user=$_.Name

Write-Host "Arreglando permisos para $user"

icacls "$FTP\vhome\$user" /grant "$user:(OI)(CI)M"

}

Restart-Service ftpsvc

Write-Host "Permisos aplicados correctamente."