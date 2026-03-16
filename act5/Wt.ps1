Import-Module WebAdministration -ErrorAction SilentlyContinue

$BASE="C:\FTP"
$LOCAL="C:\FTP\LocalUser"
$PUBLIC="C:\FTP\LocalUser\Public"
$GENERAL="C:\FTP\LocalUser\Public\General"

function Preparar-ServidorFTP {

Write-Host "`n===== CONFIGURANDO SERVIDOR FTP =====" -ForegroundColor Cyan

if(Test-Path $BASE){

Write-Host "Limpiando permisos anteriores..." -ForegroundColor Yellow

cmd /c "takeown /f C:\FTP /r /d y >nul 2>nul"
cmd /c "icacls C:\FTP /grant Administrators:(OI)(CI)F /T /Q >nul 2>nul"

icacls $BASE /reset /T /C | Out-Null

}

Write-Host "Instalando IIS y FTP..." -ForegroundColor Cyan

Install-WindowsFeature Web-Server,Web-FTP-Service,Web-FTP-Server,Web-Basic-Auth -IncludeAllSubFeature -ErrorAction SilentlyContinue | Out-Null

Import-Module WebAdministration

Write-Host "Configurando Firewall..." -ForegroundColor Cyan
New-NetFirewallRule -DisplayName "FTP" -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow -ErrorAction SilentlyContinue | Out-Null

Write-Host "Creando estructura de carpetas..." -ForegroundColor Cyan

New-Item $GENERAL -ItemType Directory -Force | Out-Null
New-Item "$BASE\Reprobados" -ItemType Directory -Force | Out-Null
New-Item "$BASE\Recursadores" -ItemType Directory -Force | Out-Null

Write-Host "Configurando permisos base..." -ForegroundColor Cyan

icacls $BASE /inheritance:r | Out-Null

icacls $BASE /grant "Administrators:(OI)(CI)F" | Out-Null
icacls $BASE /grant "SYSTEM:(OI)(CI)F" | Out-Null
icacls $BASE /grant "IIS_IUSRS:(OI)(CI)RX" | Out-Null

icacls $PUBLIC /grant "IUSR:(OI)(CI)RX" | Out-Null

if(!(Get-WebSite -Name FTP -ErrorAction SilentlyContinue)){

New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath $BASE | Out-Null

}

Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.userIsolation.mode -Value "IsolateAllDirectories"

Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value 0

Clear-WebConfiguration "/system.ftpServer/security/authorization" -PSPath IIS:\ -Location FTP

Add-WebConfiguration "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="?";permissions=1} -PSPath IIS:\ -Location FTP
Add-WebConfiguration "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="*";permissions=3} -PSPath IIS:\ -Location FTP

Restart-Service ftpsvc

Write-Host "Servidor FTP listo." -ForegroundColor Green
}

function Generar-GruposClase {

$grupos=@("Reprobados","Recursadores")

foreach($g in $grupos){

if(!(Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)){

New-LocalGroup $g | Out-Null
Write-Host "Grupo $g creado"

}

}

}

function Alta-NuevoUsuario {

do{

$usuario=Read-Host "Nombre del alumno"

if(Get-LocalUser $usuario -ErrorAction SilentlyContinue){

Write-Host "El usuario ya existe." -ForegroundColor Red

}

}while(Get-LocalUser $usuario -ErrorAction SilentlyContinue)

$password=Read-Host "Contraseña"

Write-Host "Grupo: 1 Reprobados / 2 Recursadores"
$op=Read-Host "Seleccione"

if($op -eq "1"){
$grupo="Reprobados"
}else{
$grupo="Recursadores"
}

Write-Host "Creando usuario..." -ForegroundColor Yellow

net user $usuario $password /add | Out-Null

Add-LocalGroupMember -Group $grupo -Member $usuario -ErrorAction SilentlyContinue

$home="$LOCAL\$usuario"

New-Item $home -ItemType Directory -Force | Out-Null

cmd /c mklink /D "$home\General" "$GENERAL" | Out-Null
cmd /c mklink /D "$home\$grupo" "$BASE\$grupo" | Out-Null

Write-Host "Aplicando permisos..." -ForegroundColor Yellow

icacls $home /inheritance:r | Out-Null

icacls $home /grant "$usuario:(OI)(CI)M" | Out-Null
icacls $home /grant "Administrators:(OI)(CI)F" | Out-Null
icacls $home /grant "SYSTEM:(OI)(CI)F" | Out-Null

icacls $LOCAL /grant "$usuario:(RX)" | Out-Null

icacls "$BASE\Reprobados" /grant "Reprobados:(OI)(CI)M" | Out-Null
icacls "$BASE\Recursadores" /grant "Recursadores:(OI)(CI)M" | Out-Null

icacls $GENERAL /grant "Users:(OI)(CI)M" | Out-Null

Write-Host "Usuario creado correctamente." -ForegroundColor Green

}

function Mover-UsuarioDeGrupo {

param([string]$usuario)

if(!(Get-LocalUser $usuario -ErrorAction SilentlyContinue)){

Write-Host "Usuario no existe." -ForegroundColor Red
return

}

Write-Host "Nuevo grupo:"
Write-Host "1 Reprobados"
Write-Host "2 Recursadores"

$op=Read-Host "Seleccione"

if($op -eq "1"){
$grupoDestino="Reprobados"
}else{
$grupoDestino="Recursadores"
}

$grupoViejo=""

if(Get-LocalGroupMember Reprobados -ErrorAction SilentlyContinue | Where {$_.Name -like "*$usuario"}){

$grupoViejo="Reprobados"

}

if(Get-LocalGroupMember Recursadores -ErrorAction SilentlyContinue | Where {$_.Name -like "*$usuario"}){

$grupoViejo="Recursadores"

}

Remove-LocalGroupMember Reprobados $usuario -ErrorAction SilentlyContinue
Remove-LocalGroupMember Recursadores $usuario -ErrorAction SilentlyContinue

Add-LocalGroupMember $grupoDestino $usuario -ErrorAction SilentlyContinue

$home="$LOCAL\$usuario"

cmd /c rmdir "$home\Reprobados" 2>nul
cmd /c rmdir "$home\Recursadores" 2>nul

cmd /c mklink /D "$home\$grupoDestino" "$BASE\$grupoDestino" | Out-Null

Write-Host "Limpiando permisos anteriores..." -ForegroundColor Yellow

icacls "$BASE\Reprobados" /remove $usuario /T /C | Out-Null
icacls "$BASE\Recursadores" /remove $usuario /T /C | Out-Null

Restart-Service ftpsvc

Write-Host "Usuario movido correctamente." -ForegroundColor Green

}

# MENU

do{

Clear-Host

Write-Host "============================"
Write-Host " PANEL ADMIN FTP"
Write-Host "============================"
Write-Host "1 Instalar Servidor"
Write-Host "2 Crear Usuarios"
Write-Host "3 Cambiar Usuario de Grupo"
Write-Host "4 Salir"

$op=Read-Host "Seleccione"

switch($op){

"1"{

Preparar-ServidorFTP
Generar-GruposClase
Pause

}

"2"{

$n=Read-Host "Cantidad de usuarios"

for($i=1;$i -le $n;$i++){

Write-Host "`nUsuario $i de $n"
Alta-NuevoUsuario

}

Pause

}

"3"{

$user=Read-Host "Usuario"
Mover-UsuarioDeGrupo $user
Pause

}

}

}while($op -ne "4")