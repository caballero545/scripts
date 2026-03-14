# ===============================================
# SCRIPT 2: CREACIÓN / REPARACIÓN DE USUARIOS
# ===============================================
$BASE = "C:\FTP"
$LOCALUSER = "C:\FTP\LocalUser"
$GENERAL = "C:\FTP\LocalUser\Public\general"
$GRP_REPRO = "C:\FTP\reprobados"
$GRP_RECUR = "C:\FTP\recursadores"

# 1. Verificar Carpeta Raíz
if (!(Test-Path $BASE)) { 
    Write-Host "ERROR: No existe C:\FTP. Corre el Script 1 primero." -ForegroundColor Red
    exit 
}

$n = Read-Host "¿Cuántos alumnos vas a procesar?"

for ($i = 1; $i -le $n; $i++) {
    Write-Host "`n--- Procesando Usuario $i ---" -ForegroundColor Cyan
    $usuario = Read-Host "Nombre del alumno (ej. k1)"
    
    # 2. Crear usuario si no existe
    if (!(Get-LocalUser $usuario -ErrorAction SilentlyContinue)) {
        $pass = Read-Host "Contraseña para $usuario" -AsSecureString
        New-LocalUser $usuario -Password $pass | Out-Null
        Add-LocalGroupMember ftpusers $usuario -ErrorAction SilentlyContinue
        Write-Host "Usuario $usuario creado en el sistema." -ForegroundColor Yellow
    }

    # 3. Asignar Grupo
    $op = Read-Host "Grupo (1: Reprobados, 2: Recursadores)"
    $nomGrupo = if ($op -eq "1") { "reprobados" } else { "recursadores" }
    $rutaGrupo = if ($op -eq "1") { $GRP_REPRO } else { $GRP_RECUR }
    Add-LocalGroupMember $nomGrupo $usuario -ErrorAction SilentlyContinue

    # 4. LA PARTE CRÍTICA: Crear la "casa" del usuario
    $uHome = "$LOCALUSER\$usuario"
    if (!(Test-Path $uHome)) { 
        New-Item $uHome -ItemType Directory -Force | Out-Null 
    }

    # 5. Crear los "puentes" (Links)
    # Borramos links viejos por si acaso
    cmd /c rmdir "$uHome\general" 2>$null
    cmd /c rmdir "$uHome\$nomGrupo" 2>$null
    
    # Creamos los nuevos (estilo compa)
    cmd /c mklink /D "$uHome\general" "$GENERAL" | Out-Null
    cmd /c mklink /D "$uHome\$nomGrupo" "$rutaGrupo" | Out-Null

    # 6. Permisos NTFS (Usando ${usuario} para evitar el error anterior)
    icacls $uHome /inheritance:r | Out-Null
    icacls $uHome /grant "Administradores:(OI)(CI)F" | Out-Null
    icacls $uHome /grant "${usuario}:(OI)(CI)M" | Out-Null

    Write-Host "¡Listo! Carpeta y permisos para $usuario configurados." -ForegroundColor Green
}

Restart-Service ftpsvc
Write-Host "`nServicio reiniciado. Prueba loguearte ahora." -ForegroundColor Cyan