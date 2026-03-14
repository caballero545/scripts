Import-Module WebAdministration

Write-Host "INSTALANDO IIS FTP..."

Install-WindowsFeature Web-Server,Web-Mgmt-Console,Web-FTP-Server,Web-FTP-Service -IncludeManagementTools

$appcmd="$env:windir\system32\inetsrv\appcmd.exe"

& $appcmd unlock config -section:system.ftpServer/security/authentication
& $appcmd unlock config -section:system.ftpServer/security/authorization

Write-Host "CREANDO GRUPOS"

$grupos="reprobados","recursadores","ftpusers"

foreach($g in $grupos){
if(!(Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)){
New-LocalGroup $g
}
}

Write-Host "CREANDO ESTRUCTURA FTP"

New-Item C:\FTP -ItemType Directory -Force
New-Item C:\FTP\general -ItemType Directory -Force
New-Item C:\FTP\reprobados -ItemType Directory -Force
New-Item C:\FTP\recursadores -ItemType Directory -Force
New-Item C:\FTP\LocalUser -ItemType Directory -Force

Write-Host "PERMISOS BASE"

icacls C:\FTP /inheritance:r
icacls C:\FTP /grant "Administrators:(OI)(CI)F"
icacls C:\FTP /grant "SYSTEM:(OI)(CI)F"
icacls C:\FTP /grant "IIS_IUSRS:(OI)(CI)RX"

icacls C:\FTP\general /grant "ftpusers:(OI)(CI)M"
icacls C:\FTP\reprobados /grant "reprobados:(OI)(CI)M"
icacls C:\FTP\recursadores /grant "recursadores:(OI)(CI)M"

Write-Host "CREANDO SITIO FTP"

if(!(Test-Path "IIS:\Sites\FTP")){
New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath "C:\FTP"
}

Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true

Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.userIsolation.mode -Value 3

Write-Host "REGLAS FTP"

Clear-WebConfiguration system.ftpServer/security/authorization -PSPath IIS:\Sites\FTP

Add-WebConfiguration system.ftpServer/security/authorization -PSPath IIS:\Sites\FTP -Value @{accessType="Allow";users="anonymous";permissions="Read"}

Add-WebConfiguration system.ftpServer/security/authorization -PSPath IIS:\Sites\FTP -Value @{accessType="Allow";roles="ftpusers";permissions="Read,Write"}

Restart-Service ftpsvc

Write-Host "FTP INSTALADO CORRECTAMENTE"