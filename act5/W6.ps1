$LOCALUSER="C:\FTP\LocalUser"

Write-Host "USUARIOS REGISTRADOS:" -ForegroundColor Cyan
Get-LocalGroupMember ftpusers -ErrorAction SilentlyContinue | Select Name

$usuario = Read-Host "Usuario a eliminar"

if (!(Get-LocalUser $usuario -ErrorAction SilentlyContinue)) {
    Write-Host "Error: El usuario no existe." -ForegroundColor Red ; exit
}

# 1. Quitar de grupos
$grupos = "reprobados","recursadores","ftpusers"
foreach($g in $grupos){
    Remove-LocalGroupMember $g -Member $usuario -ErrorAction SilentlyContinue
}

# 2. Eliminar cuenta de Windows
Remove-LocalUser $usuario -ErrorAction SilentlyContinue

# 3. Borrar carpeta física y enlaces
if(Test-Path "$LOCALUSER\$usuario"){
    # Forzamos borrado de enlaces primero para evitar problemas de permisos
    cmd /c rmdir /S /Q "$LOCALUSER\$usuario" 2>$null
    Write-Host "Carpeta de usuario eliminada." -ForegroundColor Yellow
}

Write-Host "Usuario $usuario borrado del sistema." -ForegroundColor Green
Restart-Service ftpsvc