$BASE="C:\FTP\usuarios"
$VHOME="C:\FTP\vhome"
$GENERAL="C:\FTP\general"

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

    # Crear usuario y grupos
    New-LocalUser $usuario -Password $pass | Out-Null
    Add-LocalGroupMember -Group $grupo -Member $usuario
    Add-LocalGroupMember -Group ftpusers -Member $usuario

    # --- ESTRUCTURA ---
    # Solo creamos la raíz del usuario y su carpeta privada real
    New-Item "$VHOME\$usuario" -ItemType Directory -Force | Out-Null
    New-Item "$VHOME\$usuario\$usuario" -ItemType Directory -Force | Out-Null

    # --- JUNCTIONS (Como bind mounts) ---
    # NOTA: mklink requiere que la carpeta de destino NO exista. 
    # Si por error ya existen, las borramos para que el link funcione.
    if (Test-Path "$VHOME\$usuario\general") { Remove-Item "$VHOME\$usuario\general" -Force }
    if (Test-Path "$VHOME\$usuario\$grupo") { Remove-Item "$VHOME\$usuario\$grupo" -Force }

    cmd /c mklink /J "$VHOME\$usuario\general" "$GENERAL"
    cmd /c mklink /J "$VHOME\$usuario\$grupo" "$BASE\$grupo"

    # --- PERMISOS (El fix de las llaves ${}) ---
    # Root del usuario (Solo lectura/ejecución para entrar)
    icacls "$VHOME\$usuario" /grant "${usuario}:(RX)"
    
    # Carpeta privada (Control total)
    icacls "$VHOME\$usuario\$usuario" /grant "${usuario}:(OI)(CI)M"

    # Permisos en las carpetas compartidas reales
    icacls "$GENERAL" /grant "${usuario}:(M)"
    icacls "$BASE\$grupo" /grant "${usuario}:(M)"

    Write-Host "Usuario $usuario creado y configurado correctamente." -ForegroundColor Green
}

Restart-Service ftpsvc
Write-Host "Servicio FTP reiniciado." -ForegroundColor Cyan