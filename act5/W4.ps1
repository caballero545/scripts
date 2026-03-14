$BASE="C:\FTP"
$LOCALUSER="C:\FTP\LocalUser"

$usuario = Read-Host "Usuario a mover"

if (!(Get-LocalUser $usuario -ErrorAction SilentlyContinue)) {
    Write-Host "Usuario no existe." -ForegroundColor Red ; exit
}

Write-Host "1) Reprobados | 2) Recursadores"
$op = Read-Host "Elija destino"

Remove-LocalGroupMember reprobados -Member $usuario -ErrorAction SilentlyContinue
Remove-LocalGroupMember recursadores -Member $usuario -ErrorAction SilentlyContinue

# Ruta de la 'casa' del usuario
$uPath = "$LOCALUSER\$usuario"

# Borrar links anteriores (se usa /D porque son directorios)
cmd /c rmdir "$uPath\reprobados" 2>$null
cmd /c rmdir "$uPath\recursadores" 2>$null

if($op -eq "1"){
    Add-LocalGroupMember reprobados -Member $usuario
    cmd /c mklink /D "$uPath\reprobados" "$BASE\reprobados" | Out-Null
    Write-Host "$usuario movido a Reprobados." -ForegroundColor Green
}
elseif($op -eq "2"){
    Add-LocalGroupMember recursadores -Member $usuario
    cmd /c mklink /D "$uPath\recursadores" "$BASE\recursadores" | Out-Null
    Write-Host "$usuario movido a Recursadores." -ForegroundColor Green
}

Restart-Service ftpsvc