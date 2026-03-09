while ($true) {

Clear-Host

Write-Host "================================="
Write-Host "       ADMINISTRADOR FTP"
Write-Host "================================="
Write-Host "1) Instalar / reparar FTP"
Write-Host "2) Crear usuarios FTP"
Write-Host "3) Configurar permisos FTP"
Write-Host "4) Cambiar grupo de usuario"
Write-Host "5) Ver usuarios FTP"
Write-Host "6) Eliminar usuario FTP"
Write-Host "7) Configurar FTP anonimo"
Write-Host "8) Reiniciar FTP"
Write-Host "0) Salir"
Write-Host "================================="

$op = Read-Host "Seleccione una opcion"

switch ($op) {

"1" {
    .\W1.ps1
    pause
}

"2" {
    .\W2.ps1
    pause
}

"3" {
    .\W3.ps1
    pause
}

"4" {
    .\W4.ps1
    pause
}

"5" {
    .\W5.ps1
    pause
}

"6" {
    .\W6.ps1
    pause
}

"7" {
    .\W7.ps1
    pause
}

"8" {
    .\Wr.ps1
    pause
}

"0" { exit }

default {
    Write-Host "Opcion invalida"
    Start-Sleep 2
}

}

}