Write-Host ""
Write-Host "================================="
Write-Host "   VERIFICACION DEL SERVIDOR FTP"
Write-Host "================================="

$FTP="C:\FTP"
$BASE="C:\FTP\usuarios"
$VHOME="C:\FTP\vhome"

Write-Host ""
Write-Host "----- Estado del servicio FTP -----"

Get-Service ftpsvc

Write-Host ""
Write-Host "----- Sitio FTP en IIS -----"

Import-Module WebAdministration
Get-ChildItem IIS:\Sites

Write-Host ""
Write-Host "----- Modo de aislamiento de usuarios -----"

Get-ItemProperty IIS:\Sites\FTP | Select ftpServer.userIsolation.mode

Write-Host ""
Write-Host "----- Grupos del sistema -----"

Get-LocalGroup reprobados
Get-LocalGroup recursadores
Get-LocalGroup ftpusers

Write-Host ""
Write-Host "----- Miembros del grupo reprobados -----"

Get-LocalGroupMember reprobados -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "----- Miembros del grupo recursadores -----"

Get-LocalGroupMember recursadores -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "----- Estructura principal FTP -----"

Get-ChildItem $FTP

Write-Host ""
Write-Host "----- Carpetas de grupos -----"

Get-ChildItem $BASE

Write-Host ""
Write-Host "----- Homes de usuarios (vhome) -----"

Get-ChildItem $VHOME

Write-Host ""
Write-Host "----- Junctions dentro de vhome -----"

Get-ChildItem $VHOME -Recurse | Where-Object {$_.LinkType}

Write-Host ""
Write-Host "----- Permisos NTFS de GENERAL -----"

icacls "$FTP\general"

Write-Host ""
Write-Host "----- Permisos NTFS REPROBADOS -----"

icacls "$BASE\reprobados"

Write-Host ""
Write-Host "----- Permisos NTFS RECURSADORES -----"

icacls "$BASE\recursadores"

Write-Host ""
Write-Host "----- Permisos de cada usuario -----"

Get-ChildItem $VHOME | ForEach-Object {

$user=$_.Name

Write-Host ""
Write-Host "Usuario:" $user

icacls "$VHOME\$user"

}

Write-Host ""
Write-Host "----- Acceso anonimo -----"

Get-ItemProperty IIS:\Sites\FTP | Select ftpServer.security.authentication.anonymousAuthentication.enabled

Write-Host ""
Write-Host "================================="
Write-Host "   FIN DE VERIFICACION FTP"
Write-Host "================================="