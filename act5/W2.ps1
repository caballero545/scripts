$BASE="C:\FTP\usuarios"
$VHOME="C:\FTP\vhome\LocalUser"
$GENERAL="C:\FTP\general"

$n = Read-Host "Cuantos usuarios"

for ($i=1; $i -le $n; $i++) {

    $usuario = Read-Host "Usuario"

    if (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue) {
        Write-Host "Usuario ya existe" -ForegroundColor Yellow
        continue
    }

    $pass = Read-Host "Password" -AsSecureString

    Write-Host "1) reprobados"
    Write-Host "2) recursadores"

    $g = Read-Host "Grupo"

    if ($g -eq "1") { $grupo="reprobados" }
    elseif ($g -eq "2") { $grupo="recursadores" }
    else {
        Write-Host "Grupo invalido"
        continue
    }

    # CREAR USUARIO
    New-LocalUser $usuario -Password $pass | Out-Null

    Add-LocalGroupMember -Group $grupo -Member $usuario
    Add-LocalGroupMember -Group ftpusers -Member $usuario

    # ---------- HOME IIS ----------
    New-Item "$VHOME\$usuario" -ItemType Directory -Force | Out-Null
    New-Item "$VHOME\$usuario\$usuario" -ItemType Directory -Force | Out-Null

    # ---------- LINKS ----------
    cmd /c mklink /J "$VHOME\$usuario\general" "$GENERAL"
    cmd /c mklink /J "$VHOME\$usuario\$grupo" "$BASE\$grupo"

    # ---------- PERMISOS HOME ----------
    icacls "$VHOME\$usuario" /inheritance:r
    icacls "$VHOME\$usuario" /grant "${usuario}:(OI)(CI)M"
    icacls "$VHOME\$usuario\$usuario" /grant "${usuario}:(OI)(CI)M"

    # ---------- PERMISOS GENERAL ----------
    icacls "$GENERAL" /grant "${usuario}:(M)"

    # ---------- PERMISOS GRUPO ----------
    icacls "$BASE\$grupo" /grant "${usuario}:(M)"

    Write-Host "Usuario $usuario creado correctamente." -ForegroundColor Green
}

Restart-Service ftpsvc
Write-Host "FTP reiniciado."