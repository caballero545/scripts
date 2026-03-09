$usuario = Read-Host "Usuario"

Write-Host "1) reprobados"
Write-Host "2) recursadores"

$op = Read-Host

if ($op -eq "1") { $grupo="reprobados" }
else { $grupo="recursadores" }

Add-LocalGroupMember -Group $grupo -Member $usuario

Write-Host "Grupo cambiado."