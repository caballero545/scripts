$BASE="C:\FTP\usuarios"
$VHOME="C:\FTP\vhome\LocalUser"

$usuario=Read-Host "Usuario"

Write-Host "1 reprobados"
Write-Host "2 recursadores"

$op=Read-Host "Grupo"

Remove-LocalGroupMember reprobados -Member $usuario -ErrorAction SilentlyContinue
Remove-LocalGroupMember recursadores -Member $usuario -ErrorAction SilentlyContinue

Remove-Item "$VHOME\$usuario\reprobados" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item "$VHOME\$usuario\recursadores" -Force -Recurse -ErrorAction SilentlyContinue

if($op -eq "1"){

Add-LocalGroupMember reprobados -Member $usuario
cmd /c mklink /J "$VHOME\$usuario\reprobados" "$BASE\reprobados"

}

elseif($op -eq "2"){

Add-LocalGroupMember recursadores -Member $usuario
cmd /c mklink /J "$VHOME\$usuario\recursadores" "$BASE\recursadores"

}

Restart-Service ftpsvc