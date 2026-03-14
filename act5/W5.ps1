Write-Host "================================="
Write-Host "     USUARIOS FTP REGISTRADOS"
Write-Host "================================="

$users = Get-LocalGroupMember ftpusers -ErrorAction SilentlyContinue

if ($null -eq $users) { Write-Host "No hay usuarios aún." }
else {
    foreach ($u in $users){
        $nombre=$u.Name.Split("\")[-1]
        $grupo="sin grupo"

        if(Get-LocalGroupMember reprobados -ErrorAction SilentlyContinue | Where-Object {$_.Name -match $nombre}){ $grupo="reprobados" }
        elseif(Get-LocalGroupMember recursadores -ErrorAction SilentlyContinue | Where-Object {$_.Name -match $nombre}){ $grupo="recursadores" }

        Write-Host "$nombre - $grupo" -ForegroundColor Cyan
    }
}