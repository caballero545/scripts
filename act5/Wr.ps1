Write-Host "Reiniciando servidor FTP..."

Restart-Service ftpsvc

Get-Service ftpsvc

Write-Host "Servidor FTP listo."