Write-Host "================================="
Write-Host "     USUARIOS FTP REGISTRADOS"
Write-Host "================================="

$users = Get-LocalGroupMember ftpusers -ErrorAction SilentlyContinue

if ($null -eq $users) { 
    Write-Host "No hay usuarios registrados." -ForegroundColor Yellow 
}
else {
    foreach ($u in $users){
        $nombre = $u.Name.Split("\")[-1]
        $grupo = "Sin grupo específico"

        if(Get-LocalGroupMember reprobados -ErrorAction SilentlyContinue | Where-Object {$_.Name -match $nombre}){ $grupo = "REPROBADOS" }
        elseif(Get-LocalGroupMember recursadores -ErrorAction SilentlyContinue | Where-Object {$_.Name -match $nombre}){ $grupo = "RECURSADORES" }

        Write-Host "Alumno: $nombre | Grupo: $grupo" -ForegroundColor Cyan
    }
}