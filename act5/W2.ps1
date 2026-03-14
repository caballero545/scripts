# ===============================================
# SCRIPT 2: CREACIÓN DE USUARIOS (VERSIÓN FINAL)
# ===============================================

$BASE="C:\FTP"
$GENERAL="C:\FTP\LocalUser\Public\general"
$GRP1="C:\FTP\reprobados"
$GRP2="C:\FTP\recursadores"
$LOCALUSER="C:\FTP\LocalUser"

# Verificación de carpeta base
if(!(Test-Path $BASE)){
    Write-Host "ERROR: No existe la carpeta FTP base en C:\FTP" -ForegroundColor Red
    exit
}

$n = Read-Host "Numero de usuarios a crear"
if($n -notmatch '^\d+$'){ Write-Host "Numero invalido." -ForegroundColor Red; exit }

for($i=1; $i -le $n; $i++){
    Write-Host "`n==============================="
    Write-Host "    CREACION DE USUARIO $i"
    Write-Host "==============================="

    $usuario = Read-Host "Nombre de usuario"
    if([string]::IsNullOrWhiteSpace($usuario)){ Write-Host "Usuario invalido" -ForegroundColor Red; continue }
    if(Get-LocalUser $usuario -ErrorAction SilentlyContinue){ Write-Host "El usuario $usuario ya existe. Saltando..." -ForegroundColor Yellow; continue }

    $pass = Read-Host "Password (puedes usar 1234)" -AsSecureString

    Write-Host "Seleccione Grupo:"
    Write-Host "1 = reprobados"
    Write-Host "2 = recursadores"
    $op = Read-Host "Opcion"

    if($op -eq "1"){ $grupo="reprobados"; $rutagrupo=$GRP1 }
    elseif($op -eq "2"){ $grupo="recursadores"; $rutagrupo=$GRP2 }
    else{ Write-Host "Grupo invalido." -ForegroundColor Red; continue }

    try {
        # Crear usuario en el sistema
        New-LocalUser $usuario -Password $pass -ErrorAction Stop | Out-Null
        Add-LocalGroupMember ftpusers $usuario -ErrorAction SilentlyContinue
        Add-LocalGroupMember $grupo $usuario -ErrorAction SilentlyContinue

        # Definir carpetas (Cambiamos $home por $userHome para evitar errores de sistema)
        $userHome = "$LOCALUSER\$usuario"
        $userPersonal = "$userHome\$usuario"

        # Crear directorios físicos
        if(!(Test-Path $userHome)){ New-Item $userHome -ItemType Directory -Force | Out-Null }
        if(!(Test-Path $userPersonal)){ New-Item $userPersonal -ItemType Directory -Force | Out-Null }

        # Crear Enlaces Simbólicos (Puentes de aislamiento)
        cmd /c mklink /D "$userHome\general" "$GENERAL" | Out-Null
        cmd /c mklink /D "$userHome\$grupo" "$rutagrupo" | Out-Null

        # Aplicar Permisos NTFS (Usando ${usuario} para evitar error de sintaxis)
        icacls $userHome /grant "${usuario}:(OI)(CI)M" /Q | Out-Null
        icacls $userPersonal /grant "${usuario}:(OI)(CI)M" /Q | Out-Null

        Write-Host "Usuario $usuario creado y configurado correctamente." -ForegroundColor Green
    }
    catch {
        Write-Host "Error fatal al crear el usuario: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Reiniciar para aplicar cambios en IIS
Restart-Service ftpsvc
Write-Host "`nPROCESO TERMINADO - SERVICIO FTP REINICIADO" -ForegroundColor Cyan