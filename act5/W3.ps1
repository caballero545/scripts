$FTP="C:\FTP"

Write-Host "Configurando permisos seguros..."

icacls $FTP /inheritance:r

icacls $FTP /grant "Administrators:(OI)(CI)F"

icacls "$FTP\general" /grant "IUSR:(RX)"

Restart-Service ftpsvc