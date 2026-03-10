$VHOME="C:\FTP\vhome"

Write-Host "================================="
Write-Host "     USUARIOS FTP REGISTRADOS"
Write-Host "================================="

Get-ChildItem $VHOME -Directory | ForEach-Object {

$user=$_.Name

if(Get-LocalGroupMember reprobados -ErrorAction SilentlyContinue | Where {$_.Name -match $user}){
$grupo="reprobados"
}
elseif(Get-LocalGroupMember recursadores -ErrorAction SilentlyContinue | Where {$_.Name -match $user}){
$grupo="recursadores"
}
else{
$grupo="sin grupo"
}

Write-Host "$user  -  $grupo"

}