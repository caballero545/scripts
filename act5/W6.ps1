$VHOME="C:\FTP\vhome\LocalUser"

Write-Host "Usuarios existentes:"

Get-ChildItem $VHOME -Directory | ForEach-Object {
Write-Host $_.Name
}

$usuario = Read-Host "Usuario a eliminar"

if (!(Get-LocalUser $usuario -ErrorAction SilentlyContinue)) {
Write-Host "Usuario no existe"
exit
}

# eliminar usuario del sistema
Remove-LocalUser $usuario

# eliminar carpeta FTP
if(Test-Path "$VHOME\$usuario"){
Remove-Item "$VHOME\$usuario" -Recurse -Force
}

Write-Host "Usuario eliminado correctamente."

Restart-Service ftpsvc