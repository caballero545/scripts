$ROOT="C:\FTP"

Write-Host "CREACION DE USUARIOS FTP"

$n = Read-Host "Cuantos usuarios deseas crear"

for ($i=1; $i -le $n; $i++) {

$usuario = Read-Host "Nombre de usuario"

if (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue) {
Write-Host "Usuario ya existe"
continue
}

$pass = Read-Host "Contraseña" -AsSecureString

Write-Host "1) reprobados"
Write-Host "2) recursadores"

$g = Read-Host "Grupo"

if ($g -eq "1") {
$grupo="reprobados"
}
elseif ($g -eq "2") {
$grupo="recursadores"
}
else {
Write-Host "Grupo invalido"
continue
}

New-LocalUser $usuario -Password $pass
Add-LocalGroupMember -Group $grupo -Member $usuario
Add-LocalGroupMember -Group ftpusers -Member $usuario

New-Item -ItemType Directory -Path "$ROOT\$usuario" -Force

icacls "$ROOT\$usuario" /grant "${usuario}:(OI)(CI)M"
icacls "$ROOT\general" /grant "${usuario}:(OI)(CI)M"
icacls "$ROOT\$grupo" /grant "${usuario}:(OI)(CI)M"

Write-Host "Usuario creado correctamente."

}

Restart-Service ftpsvc