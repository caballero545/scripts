$ROOT="C:\FTP"

Write-Host "Usuarios existentes:"

Get-ChildItem $ROOT -Directory | Where-Object { $_.Name -notmatch "general|reprobados|recursadores" } | ForEach-Object { Write-Host $_.Name }

$usuario = Read-Host "Usuario a eliminar"

if (!(Get-LocalUser $usuario -ErrorAction SilentlyContinue)) {
Write-Host "Usuario no existe"
exit
}

Remove-LocalUser $usuario

Remove-Item "$ROOT\$usuario" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "Usuario eliminado correctamente."