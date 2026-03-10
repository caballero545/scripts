Import-Module ServerManager
Import-Module WebAdministration

Write-Host "Instalando FTP..."

Install-WindowsFeature Web-Server -IncludeManagementTools
Install-WindowsFeature Web-FTP-Server
Install-WindowsFeature Web-FTP-Service

New-LocalGroup reprobados -ErrorAction SilentlyContinue
New-LocalGroup recursadores -ErrorAction SilentlyContinue

New-Item C:\FTP -ItemType Directory -Force
New-Item C:\FTP\general -ItemType Directory -Force
New-Item C:\FTP\reprobados -ItemType Directory -Force
New-Item C:\FTP\recursadores -ItemType Directory -Force

if(!(Test-Path "IIS:\Sites\FTP")){
New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath "C:\FTP"
}

Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true

Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.security.ssl.dataChannelPolicy -Value 0

Restart-Service ftpsvc