$BASE="C:\FTP\usuarios"
$VHOME="C:\FTP\vhome"
$GENERAL="C:\FTP\general"

$n=Read-Host "Cuantos usuarios"

for($i=1;$i -le $n;$i++){

$usuario=Read-Host "Usuario"

if (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue) {
Write-Host "Usuario ya existe"
continue
}

$pass=Read-Host "Password" -AsSecureString

Write-Host "1) reprobados"
Write-Host "2) recursadores"

$g=Read-Host

if($g -eq "1"){ $grupo="reprobados" }
elseif($g -eq "2"){ $grupo="recursadores" }

New-LocalUser $usuario -Password $pass
Add-LocalGroupMember $grupo -Member $usuario
Add-LocalGroupMember ftpusers -Member $usuario

# estructura
New-Item "$VHOME\$usuario" -ItemType Directory -Force
New-Item "$VHOME\$usuario\general" -ItemType Directory -Force
New-Item "$VHOME\$usuario\$grupo" -ItemType Directory -Force
New-Item "$VHOME\$usuario\$usuario" -ItemType Directory -Force

# junctions (como bind mount)
cmd /c mklink /J "$VHOME\$usuario\general" "$GENERAL"
cmd /c mklink /J "$VHOME\$usuario\$grupo" "$BASE\$grupo"

# permisos
icacls "$VHOME\$usuario" /grant "$usuario:(RX)"
icacls "$VHOME\$usuario\$usuario" /grant "$usuario:(OI)(CI)M"

icacls "$GENERAL" /grant "$usuario:(M)"
icacls "$BASE\$grupo" /grant "$usuario:(M)"

}