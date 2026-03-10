$usuario=Read-Host "Usuario"

Write-Host "1) reprobados"
Write-Host "2) recursadores"

$op=Read-Host

Remove-LocalGroupMember reprobados -Member $usuario -ErrorAction SilentlyContinue
Remove-LocalGroupMember recursadores -Member $usuario -ErrorAction SilentlyContinue

if($op -eq "1"){
Add-LocalGroupMember reprobados -Member $usuario
$grupo="reprobados"
}else{
Add-LocalGroupMember recursadores -Member $usuario
$grupo="recursadores"
}

Write-Host "Usuario ahora pertenece a $grupo"