$BASE="C:\FTP\usuarios"
$VHOME="C:\FTP\vhome"

$usuario = Read-Host "Usuario"

if(!(Get-LocalUser $usuario -ErrorAction SilentlyContinue)){
Write-Host "Usuario no existe"
exit
}

Write-Host "1) reprobados"
Write-Host "2) recursadores"

$op=Read-Host "Nuevo grupo"

# quitar de ambos grupos
Remove-LocalGroupMember reprobados -Member $usuario -ErrorAction SilentlyContinue
Remove-LocalGroupMember recursadores -Member $usuario -ErrorAction SilentlyContinue

# eliminar carpeta enlace actual
Remove-Item "$VHOME\$usuario\reprobados" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item "$VHOME\$usuario\recursadores" -Recurse -Force -ErrorAction SilentlyContinue

if($op -eq "1"){

$grupo="reprobados"
Add-LocalGroupMember reprobados -Member $usuario

cmd /c mklink /J "$VHOME\$usuario\reprobados" "$BASE\reprobados"

}
elseif($op -eq "2"){

$grupo="recursadores"
Add-LocalGroupMember recursadores -Member $usuario

cmd /c mklink /J "$VHOME\$usuario\recursadores" "$BASE\recursadores"

}
else{

Write-Host "Grupo invalido"
exit

}

Write-Host "Usuario $usuario ahora pertenece a $grupo"

Restart-Service ftpsvc