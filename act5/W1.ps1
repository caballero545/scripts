Import-Module ServerManager
Import-Module WebAdministration

Install-WindowsFeature Web-Server -IncludeManagementTools
Install-WindowsFeature Web-FTP-Server
Install-WindowsFeature Web-FTP-Service

New-LocalGroup reprobados -ErrorAction SilentlyContinue
New-LocalGroup recursadores -ErrorAction SilentlyContinue
New-LocalGroup ftpusers -ErrorAction SilentlyContinue

New-Item C:\FTP -ItemType Directory -Force
New-Item C:\FTP\general -ItemType Directory -Force
New-Item C:\FTP\usuarios -ItemType Directory -Force
New-Item C:\FTP\usuarios\reprobados -ItemType Directory -Force
New-Item C:\FTP\usuarios\recursadores -ItemType Directory -Force
New-Item C:\FTP\vhome -ItemType Directory -Force

if(!(Test-Path "IIS:\Sites\FTP")){
New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath "C:\FTP"
}

Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true

Set-ItemProperty IIS:\Sites\FTP `
-name ftpServer.userIsolation.mode `
-value 3

Restart-Service ftpsvc