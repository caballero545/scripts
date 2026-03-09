$VHOME="C:\FTP\vhome"

Write-Host "Usuarios existentes:"

Get-ChildItem $VHOME | ForEach-Object { Write-Host $_.Name }

$usuario = Read-Host "Usuario a eliminar"

if (!(Get-LocalUser $usuario -ErrorAction SilentlyContinue)) {
Write-Host "Usuario no existe"
exit
}

Remove-LocalUser $usuario

Remove-Item "$VHOME\$usuario" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Usuario eliminado correctamente."