Import-Module WebAdministration

Set-ItemProperty IIS:\Sites\FTP `
-name ftpServer.security.authentication.anonymousAuthentication.enabled `
-value $true

icacls "C:\FTP\general" /grant "IUSR:(RX)"

Restart-Service ftpsvc