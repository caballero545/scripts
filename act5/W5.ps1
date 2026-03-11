$VHOME="C:\FTP\vhome\LocalUser"

Write-Host "================================="
Write-Host "     USUARIOS FTP REGISTRADOS"
Write-Host "================================="

Get-ChildItem $VHOME -Directory | ForEach-Object {

$user=$_.Name

$grupo="sin grupo"

if(Get-LocalGroupMember reprobados -ErrorAction SilentlyContinue | Where {$_.Name -match $user}){
$grupo="reprobados"
}

elseif(Get-LocalGroupMember recursadores -ErrorAction SilentlyContinue | Where {$_.Name -match $user}){
$grupo="recursadores"
}

Write-Host "$user  -  $grupo"

}