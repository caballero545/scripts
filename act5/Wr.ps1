Write-Host "Reiniciando servidor FTP..." -ForegroundColor Cyan

Restart-Service ftpsvc
Get-Service ftpsvc | Format-Table

Write-Host "Servidor FTP listo y al cien." -ForegroundColor Green