Import-Module WebAdministration

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " INSTALANDO SERVIDOR FTP IIS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Instalar IIS + FTP
Install-WindowsFeature Web-Server,Web-Mgmt-Console,Web-FTP-Server,Web-FTP-Service -IncludeManagementTools -ErrorAction SilentlyContinue

# Abrir firewall
if(!(Get-NetFirewallRule -DisplayName "FTP Server" -ErrorAction SilentlyContinue)){
New-NetFirewallRule -DisplayName "FTP Server" -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow
}

# Desactivar complejidad de contraseñas
secedit /export /cfg C:\secpol.cfg | Out-Null
(Get-Content C:\secpol.cfg) -replace 'PasswordComplexity = 1','PasswordComplexity = 0' | Out-File C:\secpol.cfg
secedit /configure /db C:\Windows\security\local.sdb /cfg C:\secpol.cfg /areas SECURITYPOLICY | Out-Null
Remove-Item C:\secpol.cfg -Force

# Crear grupos
$grupos="reprobados","recursadores","ftpusers"
foreach($g in $grupos){
if(!(Get-LocalGroup $g -ErrorAction SilentlyContinue)){
New-LocalGroup $g | Out-Null
}
}

# Crear estructura FTP
$rutas=@(
"C:\FTP",
"C:\FTP\reprobados",
"C:\FTP\recursadores",
"C:\FTP\LocalUser",
"C:\FTP\LocalUser\Public",
"C:\FTP\LocalUser\Public\General"
)

foreach($r in $rutas){
if(!(Test-Path $r)){
New-Item $r -ItemType Directory -Force | Out-Null
}
}

Write-Host "Configurando permisos base..."

icacls C:\FTP /inheritance:r | Out-Null
icacls C:\FTP /grant "Administrators:(OI)(CI)F" | Out-Null
icacls C:\FTP /grant "SYSTEM:(OI)(CI)F" | Out-Null
icacls C:\FTP /grant "IIS_IUSRS:(OI)(CI)RX" | Out-Null

icacls C:\FTP\reprobados /grant "reprobados:(OI)(CI)M" | Out-Null
icacls C:\FTP\recursadores /grant "recursadores:(OI)(CI)M" | Out-Null
icacls C:\FTP\LocalUser\Public\General /grant "ftpusers:(OI)(CI)M" | Out-Null
icacls C:\FTP\LocalUser\Public\General /grant "IUSR:(OI)(CI)RX" | Out-Null

# Crear sitio FTP
if(!(Test-Path "IIS:\Sites\FTP")){
New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath "C:\FTP"
}

# Autenticación
Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true

# Aislamiento correcto
Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.userIsolation.mode -Value "IsolateAllDirectories"

# Desactivar SSL
Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
Set-ItemProperty IIS:\Sites\FTP -Name ftpServer.security.ssl.dataChannelPolicy -Value 0

# Reglas IIS
Clear-WebConfiguration "/system.ftpServer/security/authorization" -PSPath IIS:\ -Location FTP
Add-WebConfiguration "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="?";permissions=1} -PSPath IIS:\ -Location FTP
Add-WebConfiguration "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="*";permissions=3} -PSPath IIS:\ -Location FTP

Restart-Service ftpsvc

Write-Host "SERVIDOR FTP INSTALADO CORRECTAMENTE" -ForegroundColor Green