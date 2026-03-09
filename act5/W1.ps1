Write-Host "===== CONFIGURANDO FTP ====="

Install-WindowsFeature Web-Server -IncludeManagementTools
Install-WindowsFeature Web-FTP-Server
Install-WindowsFeature Web-FTP-Service

Import-Module WebAdministration

New-LocalGroup reprobados -ErrorAction SilentlyContinue
New-LocalGroup recursadores -ErrorAction SilentlyContinue
New-LocalGroup ftpusers -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Path C:\FTP -Force
New-Item -ItemType Directory -Path C:\FTP\general -Force
New-Item -ItemType Directory -Path C:\FTP\usuarios\reprobados -Force
New-Item -ItemType Directory -Path C:\FTP\usuarios\recursadores -Force
New-Item -ItemType Directory -Path C:\FTP\vhome -Force

if (!(Test-Path "IIS:\Sites\FTP")) {

New-WebFtpSite `
-Name "FTP" `
-Port 21 `
-PhysicalPath "C:\FTP" `
-Force

}

Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true

Restart-Service ftpsvc

Write-Host "FTP configurado correctamente."