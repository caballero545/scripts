$BASE="C:\FTP"
$GENERAL="$BASE\general"
$GRP1="$BASE\reprobados"
$GRP2="$BASE\recursadores"
$LOCALUSER="$BASE\LocalUser"

if(!(Test-Path $BASE)){
Write-Host "ERROR: No existe la carpeta FTP base." -ForegroundColor Red
exit
}

$n=Read-Host "Numero de usuarios a crear"

if($n -notmatch '^\d+$'){
Write-Host "Numero invalido." -ForegroundColor Red
exit
}

for($i=1;$i -le $n;$i++){

Write-Host "==============================="
Write-Host "CREACION DE USUARIO $i"
Write-Host "==============================="

$usuario=Read-Host "Nombre de usuario"

if([string]::IsNullOrWhiteSpace($usuario)){
Write-Host "Usuario invalido" -ForegroundColor Red
continue
}

if(Get-LocalUser $usuario -ErrorAction SilentlyContinue){
Write-Host "El usuario ya existe." -ForegroundColor Yellow
continue
}

$pass=Read-Host "Password" -AsSecureString

Write-Host "Grupo:"
Write-Host "1 = reprobados"
Write-Host "2 = recursadores"

$op=Read-Host "Seleccione grupo"

if($op -eq "1"){
$grupo="reprobados"
$rutagrupo=$GRP1
}
elseif($op -eq "2"){
$grupo="recursadores"
$rutagrupo=$GRP2
}
else{
Write-Host "Grupo invalido." -ForegroundColor Red
continue
}

try{
New-LocalUser $usuario -Password $pass -ErrorAction Stop
}catch{
Write-Host "No se pudo crear el usuario." -ForegroundColor Red
continue
}

Add-LocalGroupMember ftpusers $usuario -ErrorAction SilentlyContinue
Add-LocalGroupMember $grupo $usuario -ErrorAction SilentlyContinue

$home="$LOCALUSER\$usuario"
$personal="$home\$usuario"

if(!(Test-Path $home)){
New-Item $home -ItemType Directory | Out-Null
}

if(!(Test-Path $personal)){
New-Item $personal -ItemType Directory | Out-Null
}

# enlaces
cmd /c mklink /J "$home\general" "$GENERAL" | Out-Null
cmd /c mklink /J "$home\$grupo" "$rutagrupo" | Out-Null

# permisos
icacls $home /grant "$usuario:(OI)(CI)M"
icacls $personal /grant "$usuario:(OI)(CI)M"

Write-Host "Usuario creado correctamente." -ForegroundColor Green

}

Restart-Service ftpsvc

Write-Host "================================="
Write-Host "CREACION DE USUARIOS TERMINADA"
Write-Host "================================="