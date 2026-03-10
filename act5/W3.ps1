$FTP="C:\FTP"

Write-Host "===== ARREGLANDO PERMISOS FTP ====="

icacls $FTP /grant "Users:(RX)"

icacls "$FTP\general" /grant "ftpusers:(M)"

icacls "$FTP\reprobados" /grant "reprobados:(M)"
icacls "$FTP\recursadores" /grant "recursadores:(M)"

Get-ChildItem "$FTP" -Directory | Where-Object { $_.Name -notmatch "general|reprobados|recursadores" } | ForEach-Object {

$user=$_.Name

Write-Host "Permisos para $user"

icacls "$FTP\$user" /grant "${user}:(OI)(CI)M"

}

Restart-Service ftpsvc

Write-Host "Permisos aplicados correctamente"