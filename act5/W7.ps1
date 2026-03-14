Import-Module WebAdministration

Write-Host "Configurando acceso anonimo..." -ForegroundColor Cyan

Set-ItemProperty IIS:\Sites\FTP -name ftpServer.security.authentication.anonymousAuthentication.enabled -value $true

$PUBLIC_HOME = "C:\FTP\LocalUser\Public"
if(!(Test-Path $PUBLIC_HOME)){ New-Item $PUBLIC_HOME -ItemType Directory -Force | Out-Null }

# IIS usa IUSR para anónimos
icacls "C:\FTP\LocalUser\Public\general" /grant "IUSR:(OI)(CI)RX" | Out-Null
icacls $PUBLIC_HOME /grant "IUSR:(OI)(CI)RX" | Out-Null

Restart-Service ftpsvc
Write-Host "Acceso anonimo configurado." -ForegroundColor Green