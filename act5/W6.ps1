$usuario = Read-Host "Usuario a eliminar"

Remove-LocalUser $usuario

Remove-Item "C:\FTP\vhome\$usuario" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Usuario eliminado."