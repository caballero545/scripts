$VHOME="C:\FTP\vhome"

Write-Host "================================="
Write-Host "    USUARIOS FTP REGISTRADOS"
Write-Host "================================="

Get-ChildItem $VHOME | ForEach-Object {

$usuario=$_.Name

$grupo=(Get-LocalGroup | Where-Object {
(Get-LocalGroupMember $_.Name -ErrorAction SilentlyContinue).Name -match $usuario
}).Name

Write-Host "$usuario  -  $grupo  -  $VHOME\$usuario"

}