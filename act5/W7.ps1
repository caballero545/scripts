Import-Module WebAdministration

Write-Host "Configurando acceso anonimo..."

# Habilitar anónimo en IIS
Set-ItemProperty IIS:\Sites\FTP -name ftpServer.security.authentication.anonymousAuthentication.enabled -value $true

# CREAR CARPETA PUBLIC PARA EL AISLAMIENTO
$PUBLIC_HOME = "C:\FTP\vhome\LocalUser\Public"
if(!(Test-Path $PUBLIC_HOME)){
    New-Item $PUBLIC_HOME -ItemType Directory -Force | Out-Null
    # Le creamos su acceso directo a la carpeta general
    cmd /c mklink /J "$PUBLIC_HOME\general" "C:\FTP\general"
}

# Permisos para el usuario anónimo de IIS (IUSR) con herencia (OI)(CI)
icacls "C:\FTP\general" /grant "IUSR:(OI)(CI)RX"
icacls $PUBLIC_HOME /grant "IUSR:(OI)(CI)RX"

Restart-Service ftpsvc
Write-Host "Acceso anonimo configurado (Carpeta Public creada)." -ForegroundColor Green