$BASE="C:\FTP\usuarios"
$VHOME="C:\FTP\vhome\LocalUser"
$GENERAL="C:\FTP\general"

# asegurar estructura que IIS necesita
New-Item -ItemType Directory -Path "C:\FTP\vhome\LocalUser" -Force | Out-Null

$n = Read-Host "Cuantos usuarios"

for ($i=1; $i -le $n; $i++) {

    $usuario = Read-Host "Usuario"

    if (Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue) {
        Write-Host "Usuario $usuario ya existe, saltando..." -ForegroundColor Yellow
        continue
    }

    $pass = Read-Host "Password" -AsSecureString

    Write-Host "1) reprobados"
    Write-Host "2) recursadores"
    $g = Read-Host "Seleccione grupo"

    if ($g -eq "1") { $grupo = "reprobados" }
    elseif ($g -eq "2") { $grupo = "recursadores" }
    else { 
        Write-Host "Opción inválida" -ForegroundColor Red
        continue 
    }

    # crear usuario
    New-LocalUser $usuario -Password $pass | Out-Null
    Add-LocalGroupMember -Group $grupo -Member $usuario
    Add-LocalGroupMember -Group ftpusers -Member $usuario

    # ---------- ESTRUCTURA ----------
    New-Item "$VHOME\$usuario" -ItemType Directory -Force | Out-Null
    New-Item "$VHOME\$usuario\$usuario" -ItemType Directory -Force | Out-Null

    # eliminar si existen
    if (Test-Path "$VHOME\$usuario\general") { Remove-Item "$VHOME\$usuario\general" -Force }
    if (Test-Path "$VHOME\$usuario\$grupo") { Remove-Item "$VHOME\$usuario\$grupo" -Force }

    # junctions
    cmd /c mklink /J "$VHOME\$usuario\general" "$GENERAL"
    cmd /c mklink /J "$VHOME\$usuario\$grupo" "$BASE\$grupo"

    # ---------- PERMISOS ----------
    icacls "$VHOME\$usuario" /grant "${usuario}:(RX)"
    icacls "$VHOME\$usuario\$usuario" /grant "${usuario}:(OI)(CI)M"

    icacls "$GENERAL" /grant "${usuario}:(M)"
    icacls "$BASE\$grupo" /grant "${usuario}:(M)"

    Write-Host "Usuario $usuario creado correctamente." -ForegroundColor Green
}

Restart-Service ftpsvc
Write-Host "FTP reiniciado."