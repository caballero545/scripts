Write-Host "================================="
Write-Host "     USUARIOS FTP REGISTRADOS"
Write-Host "================================="

$users = Get-LocalGroupMember ftpusers

foreach ($u in $users){

$nombre=$u.Name.Split("\")[-1]

$grupo="sin grupo"

if(Get-LocalGroupMember reprobados -ErrorAction SilentlyContinue | Where {$_.Name -match $nombre}){
$grupo="reprobados"
}

elseif(Get-LocalGroupMember recursadores -ErrorAction SilentlyContinue | Where {$_.Name -match $nombre}){
$grupo="recursadores"
}

Write-Host "$nombre - $grupo"

}