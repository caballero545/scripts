$BASE="C:\FTP\usuarios"
$VHOME="C:\FTP\vhome\LocalUser"
$GENERAL="C:\FTP\general"

$n = Read-Host "Numero de usuarios"

for ($i=1; $i -le $n; $i++) {

$usuario = Read-Host "Usuario"

if(Get-LocalUser $usuario -ErrorAction SilentlyContinue){
Write-Host "Usuario ya existe"
continue
}

$pass = Read-Host "Password" -AsSecureString

Write-Host "1 reprobados"
Write-Host "2 recursadores"

$op = Read-Host "Grupo"

if($op -eq "1"){ $grupo="reprobados" }
elseif($op -eq "2"){ $grupo="recursadores" }
else{
Write-Host "Grupo invalido"
continue
}

New-LocalUser $usuario -Password $pass

Add-LocalGroupMember ftpusers -Member $usuario
Add-LocalGroupMember $grupo -Member $usuario

Write-Host "Creando home FTP..."

New-Item "$VHOME\$usuario" -ItemType Directory -Force
New-Item "$VHOME\$usuario\$usuario" -ItemType Directory -Force

cmd /c mklink /J "$VHOME\$usuario\general" "$GENERAL"
cmd /c mklink /J "$VHOME\$usuario\$grupo" "$BASE\$grupo"

Write-Host "Asignando permisos..."

icacls "$VHOME\$usuario" /grant "${usuario}:(OI)(CI)M"
icacls "$VHOME\$usuario\$usuario" /grant "${usuario}:(OI)(CI)M"

icacls "$GENERAL" /grant "${usuario}:(M)"
icacls "$BASE\$grupo" /grant "${usuario}:(M)"

Write-Host "Usuario creado correctamente"
}

Restart-Service ftpsvc