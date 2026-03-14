$BASE="C:\FTP"
$GENERAL="C:\FTP\LocalUser\Public\general"
$GRP1="C:\FTP\reprobados"
$GRP2="C:\FTP\recursadores"
$LOCALUSER="C:\FTP\LocalUser"

if(!(Test-Path $BASE)){
    Write-Host "ERROR: No existe la carpeta FTP base." -ForegroundColor Red
    exit
}

$n=Read-Host "Numero de usuarios a crear"
if($n -notmatch '^\d+$'){ Write-Host "Numero invalido." -ForegroundColor Red; exit }

for($i=1;$i -le $n;$i++){
    Write-Host "==============================="
    Write-Host "CREACION DE USUARIO $i"
    Write-Host "==============================="

    $usuario=Read-Host "Nombre de usuario"
    if([string]::IsNullOrWhiteSpace($usuario)){ Write-Host "Usuario invalido" -ForegroundColor Red; continue }
    if(Get-LocalUser $usuario -ErrorAction SilentlyContinue){ Write-Host "El usuario ya existe." -ForegroundColor Yellow; continue }

    $pass=Read-Host "Password (gracias al parche, puede ser 1234)" -AsSecureString

    Write-Host "Grupo:"
    Write-Host "1 = reprobados"
    Write-Host "2 = recursadores"
    $op=Read-Host "Seleccione grupo"

    if($op -eq "1"){ $grupo="reprobados"; $rutagrupo=$GRP1 }
    elseif($op -eq "2"){ $grupo="recursadores"; $rutagrupo=$GRP2 }
    else{ Write-Host "Grupo invalido." -ForegroundColor Red; continue }

    try{
        New-LocalUser $usuario -Password $pass -ErrorAction Stop
    }catch{
        Write-Host "No se pudo crear el usuario." -ForegroundColor Red; continue
    }

    Add-LocalGroupMember ftpusers $usuario -ErrorAction SilentlyContinue
    Add-LocalGroupMember $grupo $usuario -ErrorAction SilentlyContinue

    $home="$LOCALUSER\$usuario"
    $personal="$home\$usuario"

    if(!(Test-Path $home)){ New-Item $home -ItemType Directory -Force | Out-Null }
    if(!(Test-Path $personal)){ New-Item $personal -ItemType Directory -Force | Out-Null }

    cmd /c mklink /D "$home\general" "$GENERAL" | Out-Null
    cmd /c mklink /D "$home\$grupo" "$rutagrupo" | Out-Null

    # Permisos
    icacls $home /grant "$usuario:(OI)(CI)M" | Out-Null
    icacls $personal /grant "$usuario:(OI)(CI)M" | Out-Null

    Write-Host "Usuario $usuario creado correctamente." -ForegroundColor Green
}

Restart-Service ftpsvc
Write-Host "CREACION DE USUARIOS TERMINADA" -ForegroundColor Cyan