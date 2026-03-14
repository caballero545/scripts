Write-Host "================================="
Write-Host "   VERIFICACION DEL SERVIDOR FTP"
Write-Host "================================="

$FTP="C:\FTP"
$VHOME="C:\FTP\LocalUser"

Write-Host "`n----- Estado del servicio FTP -----"
Get-Service ftpsvc | Format-Table

Write-Host "----- Sitio FTP en IIS -----"
Import-Module WebAdministration
Get-ChildItem IIS:\Sites | Format-Table

Write-Host "----- Modo de aislamiento de usuarios -----"
Get-ItemProperty IIS:\Sites\FTP | Select ftpServer.userIsolation.mode

Write-Host "`n----- Miembros de grupos -----"
Write-Host "Reprobados:"
Get-LocalGroupMember reprobados -ErrorAction SilentlyContinue | Select -ExpandProperty Name
Write-Host "Recursadores:"
Get-LocalGroupMember recursadores -ErrorAction SilentlyContinue | Select -ExpandProperty Name

Write-Host "`n----- Homes de usuarios (LocalUser) -----"
Get-ChildItem $VHOME | Format-Table Name

Write-Host "`n----- Junctions/Links dentro de LocalUser -----"
Get-ChildItem $VHOME -Recurse -Depth 1 -ErrorAction SilentlyContinue | Where-Object {$_.LinkType} | Format-Table FullName, Target

Write-Host "`n----- Permisos NTFS de GENERAL -----"
icacls "C:\FTP\LocalUser\Public\general"

Write-Host "`n================================="
Write-Host "   FIN DE VERIFICACION FTP"
Write-Host "================================="