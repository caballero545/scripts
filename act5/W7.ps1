Import-Module WebAdministration

Write-Host "Configurando acceso anonimo..."

Set-ItemProperty IIS:\Sites\FTP `
-name ftpServer.security.authentication.anonymousAuthentication.enabled `
-value $true

icacls "C:\FTP\general" /grant "IUSR:(RX)"

Restart-Service ftpsvc

Write-Host "Acceso anonimo habilitado."