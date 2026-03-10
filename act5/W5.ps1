Get-LocalUser | Where-Object {
Test-Path "C:\FTP\$($_.Name)"
} | ForEach-Object {

$user=$_.Name

if(Get-LocalGroupMember reprobados -ErrorAction SilentlyContinue | Where {$_.Name -match $user}){
$grupo="reprobados"
}elseif(Get-LocalGroupMember recursadores | Where {$_.Name -match $user}){
$grupo="recursadores"
}

Write-Host "$user - $grupo"

}