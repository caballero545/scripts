$usuario = Read-Host "Usuario"

if (!(Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue)) {
Write-Host "Usuario no existe"
exit
}

Write-Host "1) reprobados"
Write-Host "2) recursadores"

$op = Read-Host

if ($op -eq "1") {
$grupo="reprobados"
Remove-LocalGroupMember -Group recursadores -Member $usuario -ErrorAction SilentlyContinue
}
elseif ($op -eq "2") {
$grupo="recursadores"
Remove-LocalGroupMember -Group reprobados -Member $usuario -ErrorAction SilentlyContinue
}

Add-LocalGroupMember -Group $grupo -Member $usuario

Write-Host "Grupo cambiado a $grupo"

Restart-Service ftpsvc