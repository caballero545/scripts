$VHOME="C:\FTP\vhome\LocalUser"

Write-Host "Usuarios existentes:"

Get-LocalUser | Select Name

$usuario = Read-Host "Usuario a eliminar"

if (!(Get-LocalUser $usuario -ErrorAction SilentlyContinue)) {
    Write-Host "Usuario no existe"
    exit
}

# eliminar del grupo
Remove-LocalGroupMember reprobados -Member $usuario -ErrorAction SilentlyContinue
Remove-LocalGroupMember recursadores -Member $usuario -ErrorAction SilentlyContinue
Remove-LocalGroupMember ftpusers -Member $usuario -ErrorAction SilentlyContinue

# eliminar usuario sistema
Remove-LocalUser $usuario

# eliminar home ftp
if(Test-Path "$VHOME\$usuario"){
Remove-Item "$VHOME\$usuario" -Recurse -Force
}

Write-Host "Usuario eliminado completamente."

Restart-Service ftpsvc