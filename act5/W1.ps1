Import-Module ServerManager
Import-Module WebAdministration

Write-Host "Instalando IIS + FTP..."

Install-WindowsFeature Web-Server -IncludeManagementTools
Install-WindowsFeature Web-FTP-Server
Install-WindowsFeature Web-FTP-Service
Install-WindowsFeature Web-FTP-Ext

Write-Host "Creando grupos..."

New-LocalGroup reprobados -ErrorAction SilentlyContinue
New-LocalGroup recursadores -ErrorAction SilentlyContinue
New-LocalGroup ftpusers -ErrorAction SilentlyContinue

Write-Host "Creando estructura FTP..."

New-Item C:\FTP -ItemType Directory -Force
New-Item C:\FTP\general -ItemType Directory -Force
New-Item C:\FTP\usuarios -ItemType Directory -Force
New-Item C:\FTP\usuarios\reprobados -ItemType Directory -Force
New-Item C:\FTP\usuarios\recursadores -ItemType Directory -Force

New-Item C:\FTP\vhome -ItemType Directory -Force
New-Item C:\FTP\vhome\LocalUser -ItemType Directory -Force

Write-Host "Configurando permisos base..."

icacls C:\FTP /inheritance:r

icacls C:\FTP /grant "Administrators:(OI)(CI)F"
icacls C:\FTP /grant "SYSTEM:(OI)(CI)F"
icacls C:\FTP /grant "IIS_IUSRS:(OI)(CI)RX"
icacls C:\FTP /grant "Users:(RX)"

icacls C:\FTP\general /grant "ftpusers:(OI)(CI)M"

icacls C:\FTP\usuarios\reprobados /grant "reprobados:(OI)(CI)M"
icacls C:\FTP\usuarios\recursadores /grant "recursadores:(OI)(CI)M"

Write-Host "Creando sitio FTP..."

if(!(Test-Path "IIS:\Sites\FTP")){
New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath "C:\FTP"
}

Write-Host "Configurando autenticación..."

Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true

Write-Host "Configurando aislamiento de usuarios..."

Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.userIsolation.mode -Value 3

Write-Host "Configurando reglas de autorización..."

Clear-WebConfiguration "/system.ftpServer/security/authorization" -PSPath IIS:\

Add-WebConfiguration `
"/system.ftpServer/security/authorization" `
-value @{accessType="Allow";users="*";permissions="Read"} `
-PSPath IIS:\

Add-WebConfiguration `
"/system.ftpServer/security/authorization" `
-value @{accessType="Allow";roles="ftpusers";permissions="Read,Write"} `
-PSPath IIS:\

Restart-Service ftpsvc

Write-Host "FTP instalado y configurado correctamente."