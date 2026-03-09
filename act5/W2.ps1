$BASE="C:\FTP\usuarios"
$VHOME="C:\FTP\vhome"
$GENERAL="C:\FTP\general"

$n = Read-Host "Cuantos usuarios deseas crear"

for ($i=1; $i -le $n; $i++) {

$usuario = Read-Host "Nombre de usuario"

$pass = Read-Host "Contraseña" -AsSecureString

Write-Host "1) reprobados"
Write-Host "2) recursadores"

$g = Read-Host "Grupo"

if ($g -eq "1") { $grupo="reprobados" }
elseif ($g -eq "2") { $grupo="recursadores" }
else { Write-Host "Grupo invalido"; continue }

New-LocalUser $usuario -Password $pass
Add-LocalGroupMember -Group $grupo -Member $usuario
Add-LocalGroupMember -Group ftpusers -Member $usuario

New-Item -ItemType Directory -Path "$VHOME\$usuario" -Force
New-Item -ItemType Directory -Path "$VHOME\$usuario\$usuario" -Force

Write-Host "Usuario creado."
}