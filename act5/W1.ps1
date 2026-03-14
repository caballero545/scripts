Import-Module WebAdministration

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "1. INSTALANDO IIS Y PREPARANDO ENTORNO" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Install-WindowsFeature Web-Server,Web-Mgmt-Console,Web-FTP-Server,Web-FTP-Service -IncludeManagementTools -ErrorAction SilentlyContinue

$appcmd="$env:windir\system32\inetsrv\appcmd.exe"
& $appcmd unlock config -section:system.ftpServer/security/authentication
& $appcmd unlock config -section:system.ftpServer/security/authorization

Write-Host "Desactivando complejidad de contraseñas (para usar claves sencillas)..." -ForegroundColor Yellow
secedit /export /cfg C:\secpol.cfg | Out-Null
(Get-Content C:\secpol.cfg) -replace 'PasswordComplexity = 1', 'PasswordComplexity = 0' | Out-File C:\secpol.cfg
secedit /configure /db C:\Windows\security\local.sdb /cfg C:\secpol.cfg /areas SECURITYPOLICY | Out-Null
Remove-Item C:\secpol.cfg -Force -ErrorAction SilentlyContinue

Write-Host "CREANDO GRUPOS..."
$grupos="reprobados","recursadores","ftpusers"
foreach($g in $grupos){
    if(!(Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)){ New-LocalGroup $g | Out-Null }
}

Write-Host "CREANDO ESTRUCTURA FTP EXACTA PARA AISLAMIENTO..."
New-Item C:\FTP -ItemType Directory -Force | Out-Null
New-Item C:\FTP\reprobados -ItemType Directory -Force | Out-Null
New-Item C:\FTP\recursadores -ItemType Directory -Force | Out-Null
New-Item C:\FTP\LocalUser -ItemType Directory -Force | Out-Null
New-Item C:\FTP\LocalUser\Public -ItemType Directory -Force | Out-Null
New-Item C:\FTP\LocalUser\Public\general -ItemType Directory -Force | Out-Null

Write-Host "PERMISOS BASE..."
icacls C:\FTP /inheritance:r | Out-Null
icacls C:\FTP /grant "Administrators:(OI)(CI)F" | Out-Null
icacls C:\FTP /grant "SYSTEM:(OI)(CI)F" | Out-Null
icacls C:\FTP /grant "IIS_IUSRS:(OI)(CI)RX" | Out-Null

icacls C:\FTP\LocalUser\Public\general /grant "ftpusers:(OI)(CI)M" | Out-Null
icacls C:\FTP\reprobados /grant "reprobados:(OI)(CI)M" | Out-Null
icacls C:\FTP\recursadores /grant "recursadores:(OI)(CI)M" | Out-Null

Write-Host "CREANDO SITIO FTP..."
if(!(Test-Path "IIS:\Sites\FTP")){
    New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath "C:\FTP"
}

# Aislamiento IsolateAllDirectories (Modo 3)
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.userIsolation.mode -Value 3
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value 0

Write-Host "REGLAS FTP..."
Clear-WebConfiguration system.ftpServer/security/authorization -PSPath IIS:\Sites\FTP
Add-WebConfiguration system.ftpServer/security/authorization -PSPath IIS:\Sites\FTP -Value @{accessType="Allow";users="*";permissions="Read,Write"}

Restart-Service ftpsvc
Write-Host "FTP INSTALADO Y CONFIGURADO AL 100%" -ForegroundColor Green