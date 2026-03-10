$ROOT="C:\FTP"

Write-Host "================================="
Write-Host "    USUARIOS FTP REGISTRADOS"
Write-Host "================================="

Get-LocalUser | ForEach-Object {

$usuario=$_.Name

if(Test-Path "$ROOT\$usuario"){

$grupo=(Get-LocalGroup | Where-Object {
(Get-LocalGroupMember $_.Name -ErrorAction SilentlyContinue).Name -match $usuario
}).Name

Write-Host "$usuario  -  $grupo"

}

}