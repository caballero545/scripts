$FTP="C:\FTP"

Write-Host "===== ARREGLANDO PERMISOS FTP ====="

icacls $FTP /grant Everyone:(RX)
icacls "$FTP\general" /grant ftpusers:(M)

icacls "$FTP\usuarios\reprobados" /grant reprobados:(M)
icacls "$FTP\usuarios\recursadores" /grant recursadores:(M)

Write-Host "Permisos configurados."