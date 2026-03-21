# ==============================================================
# MAIN SCRIPT: provisioner_windows.ps1
# Provisionador HTTP Automatizado - Windows Server
# Uso: PowerShell -ExecutionPolicy Bypass -File provisioner_windows.ps1
# Requiere: Whttp.ps1 en el mismo directorio
# IMPORTANTE: Ejecutar como Administrador
# ==============================================================

# Forzar ejecucion sin confirmaciones de politica
Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue

# Resolver directorio del script de forma robusta
# $PSScriptRoot queda vacio cuando se ejecuta via SSH o con & operator
if ($PSScriptRoot -and (Test-Path $PSScriptRoot)) {
    $ScriptDir = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $ScriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
} else {
    $ScriptDir = (Get-Location).Path
}

Write-Host "  [~]   Directorio de scripts: $ScriptDir"

# Cargar archivo de funciones
$FunctionsFile = Join-Path $ScriptDir "Whttp.ps1"

if (-not (Test-Path $FunctionsFile)) {
    Write-Host "[ERROR] No se encontro: $FunctionsFile"
    Write-Host "        Pon Whttp.ps1 en el mismo directorio que este script."
    Write-Host "        Directorio buscado: $ScriptDir"
    exit 1
}

# Dot-sourcing: carga todas las funciones en el scope actual
. $FunctionsFile

# Verificar que las funciones cargaron correctamente
if (-not (Get-Command Deploy-IIS -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] Las funciones de Whttp.ps1 no se cargaron correctamente."
    Write-Host "        Intenta ejecutar manualmente: . '$FunctionsFile'"
    exit 1
}

Write-Host "  [OK]  Funciones cargadas correctamente"

# Preparar entorno (verifica admin, instala choco, limpia firewall)
Initialize-Environment

# Menu principal
while ($true) {
    Clear-Host
    Write-Host ""
    Write-Host "  PROVISIONADOR HTTP AUTOMATIZADO - SSH"
    Write-Host "  Windows Server | PowerShell $($PSVersionTable.PSVersion)"
    Write-Host ""
    Write-Host "  1) Desplegar IIS       (rol de Windows Server - obligatorio)"
    Write-Host "  2) Desplegar Apache    (Win64 via Chocolatey)"
    Write-Host "  3) Desplegar Nginx     (Windows via Chocolatey)"
    Write-Host "  4) Salir"
    Write-Host ""

    $opt = Read-Host "  Opcion [1-4]"
    $opt = $opt -replace '[^\d]', ''

    switch ($opt) {
        "1" { Deploy-IIS       }
        "2" { Deploy-ApacheWin }
        "3" { Deploy-NginxWin  }
        "4" { Write-Host ""; Write-Host "  Hasta luego."; Write-Host ""; exit 0 }
        default { Write-Host "  Opcion invalida."; Start-Sleep -Seconds 1 }
    }

    Write-Host ""
    Read-Host "  Presiona Enter para continuar"
}