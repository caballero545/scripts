$BASE="C:\FTP"
$LOCAL="C:\FTP\LocalUser"
$GENERAL="C:\FTP\LocalUser\Public\General"

if(!(Test-Path $BASE)){
Write-Host "Primero ejecuta el script de instalación." -ForegroundColor Red
exit
}

$n=Read-Host "¿Cuantos usuarios deseas crear?"

if(!($n -as [int])){
Write-Host "Cantidad inválida." -ForegroundColor Red
exit
}

for($i=1;$i -le $n;$i++){

Write-Host "Creando usuario $i de $n" -ForegroundColor Cyan

$usuario=Read-Host "Nombre del alumno"

if(Get-LocalUser $usuario -ErrorAction SilentlyContinue){
Write-Host "El usuario ya existe." -ForegroundColor Red
continue
}

$pass=Read-Host "Contraseña" -AsSecureString

New-LocalUser $usuario -Password $pass | Out-Null
Add-LocalGroupMember ftpusers $usuario

Write-Host "Grupo: 1 Reprobados / 2 Recursadores"
$op=Read-Host "Seleccione"

if($op -eq "1"){
$grupo="reprobados"
$rutaGrupo="C:\FTP\reprobados"
}
else{
$grupo="recursadores"
$rutaGrupo="C:\FTP\recursadores"
}

Add-LocalGroupMember $grupo $usuario

$home="$LOCAL\$usuario"

if(!(Test-Path $home)){
New-Item $home -ItemType Directory | Out-Null
}

# limpiar links viejos
cmd /c rmdir "$home\General" 2>$null
cmd /c rmdir "$home\$grupo" 2>$null

# crear enlaces
cmd /c mklink /D "$home\General" "$GENERAL" | Out-Null
cmd /c mklink /D "$home\$grupo" "$rutaGrupo" | Out-Null

# permisos home
icacls $home /inheritance:r | Out-Null
icacls $home /grant "Administrators:(OI)(CI)F" | Out-Null
icacls $home /grant "$usuario:(OI)(CI)M" | Out-Null

# permiso para atravesar LocalUser
icacls "C:\FTP\LocalUser" /grant "$usuario:(RX)" | Out-Null

Write-Host "Usuario $usuario listo." -ForegroundColor Green
}

Restart-Service ftpsvc