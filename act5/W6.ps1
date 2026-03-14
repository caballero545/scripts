$VHOME="C:\FTP\LocalUser"

Write-Host "Usuarios existentes en FTP:"
Get-LocalGroupMember ftpusers -ErrorAction SilentlyContinue | Select Name

$usuario = Read-Host "Usuario a eliminar"

if (!(Get-LocalUser $usuario -ErrorAction SilentlyContinue)) {
    Write-Host "Usuario no existe" -ForegroundColor Red
    exit
}

Remove-LocalGroupMember reprobados -Member $usuario -ErrorAction SilentlyContinue
Remove-LocalGroupMember recursadores -Member $usuario -ErrorAction SilentlyContinue
Remove-LocalGroupMember ftpusers -Member $usuario -ErrorAction SilentlyContinue

Remove-LocalUser $usuario

if(Test-Path "$VHOME\$usuario"){
    Remove-Item "$VHOME\$usuario" -Recurse -Force
}

Write-Host "Usuario eliminado completamente." -ForegroundColor Green
Restart-Service ftpsvc