$BASE="C:\FTP"
$VHOME="C:\FTP\LocalUser"

$usuario = Read-Host "Usuario"

Write-Host "1 reprobados"
Write-Host "2 recursadores"
$op = Read-Host "Grupo"

Remove-LocalGroupMember reprobados -Member $usuario -ErrorAction SilentlyContinue
Remove-LocalGroupMember recursadores -Member $usuario -ErrorAction SilentlyContinue

# Quitamos enlaces viejos
cmd /c rmdir "$VHOME\$usuario\reprobados" 2> $null
cmd /c rmdir "$VHOME\$usuario\recursadores" 2> $null

if($op -eq "1"){
    Add-LocalGroupMember reprobados -Member $usuario
    cmd /c mklink /D "$VHOME\$usuario\reprobados" "$BASE\reprobados" | Out-Null
    Write-Host "Movido a reprobados." -ForegroundColor Green
}
elseif($op -eq "2"){
    Add-LocalGroupMember recursadores -Member $usuario
    cmd /c mklink /D "$VHOME\$usuario\recursadores" "$BASE\recursadores" | Out-Null
    Write-Host "Movido a recursadores." -ForegroundColor Green
}

Restart-Service ftpsvc