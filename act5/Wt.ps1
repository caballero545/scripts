function Preparar-ServidorFTP {
    Write-Host "--- Iniciando configuración del Servidor FTP ---" -ForegroundColor Cyan
    
    if (Test-Path "C:\FTP") {
        Write-Host "Limpiando bloqueos de permisos anteriores..." -ForegroundColor Yellow
        # Usamos CMD para forzar la toma de posesión sin importar los errores NTFS
        cmd /c "takeown /f C:\FTP /r /d s >nul 2>nul"
        cmd /c "icacls C:\FTP /grant Administradores:(OI)(CI)F /T /Q >nul 2>nul"
        icacls "C:\FTP" /reset /t /c /l | Out-Null
    }

    # 2. INSTALACIÓN DE ROLES
    Write-Host "Instalando características de IIS y FTP..." -ForegroundColor Cyan
    Install-WindowsFeature Web-Server, Web-FTP-Service, Web-FTP-Server, Web-Basic-Auth -IncludeAllSubFeature -ErrorAction SilentlyContinue

    # 3. FIREWALL E IIS
    New-NetFirewallRule -DisplayName "Acceso_FTP" -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow -ErrorAction SilentlyContinue
    Import-Module WebAdministration

    # 4. POLÍTICA DE CONTRASEÑAS (Para permitir "1234")
    Write-Host "Desactivando complejidad de contraseñas..." -ForegroundColor Yellow
    secedit /export /cfg C:\secpol.cfg | Out-Null
    (Get-Content C:\secpol.cfg) -replace 'PasswordComplexity = 1', 'PasswordComplexity = 0' | Out-File C:\secpol.cfg
    secedit /configure /db C:\Windows\security\local.sdb /cfg C:\secpol.cfg /areas SECURITYPOLICY | Out-Null
    Remove-Item C:\secpol.cfg -Force -ErrorAction SilentlyContinue

    # 5. ESTRUCTURA DE DIRECTORIOS
    if (-not (Test-Path "C:\FTP\LocalUser\Public\General")) {
        New-Item -Path "C:\FTP\LocalUser\Public\General" -ItemType Directory -Force | Out-Null
    }

    # 6. PERMISOS NTFS BASE
    # Quitamos herencia y damos control total a los admin del sistema
    icacls "C:\FTP\LocalUser\Public" /inheritance:r | Out-Null
    icacls "C:\FTP\LocalUser\Public" /grant "IUSR:(OI)(CI)RX" | Out-Null
    icacls "C:\FTP\LocalUser\Public" /grant "SYSTEM:(OI)(CI)F" | Out-Null
    icacls "C:\FTP\LocalUser\Public" /grant "Administrators:(OI)(CI)F" | Out-Null

    # 7. CREACIÓN DEL SITIO FTP
    if (-not (Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue)) {
        New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath "C:\FTP"
    }

    # 8. CONFIGURACIÓN DE AISLAMIENTO Y AUTENTICACIÓN
    Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.userIsolation.mode -Value "IsolateAllDirectories"
    
    # SSL Desactivado (Para pruebas sin certificados)
    Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
    Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value 0

    # Reglas de Autorización IIS
    Clear-WebConfiguration -Filter "/system.ftpServer/security/authorization" -PSPath IIS:\ -Location "FTP"
    Add-WebConfiguration "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="?";permissions=1} -PSPath IIS:\ -Location "FTP"
    Add-WebConfiguration "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="*";permissions=3} -PSPath IIS:\ -Location "FTP"

    Restart-WebItem "IIS:\Sites\FTP"
    Write-Host "--- Servidor FTP listo y operativo ---" -ForegroundColor Green
}

function Generar-GruposClase {
    if ($null -eq $global:ADSI) { $global:ADSI = [ADSI]"WinNT://$env:ComputerName" }

    $grupos = @("Reprobados", "Recursadores")
    foreach ($g in $grupos) {
        if (-not ($global:ADSI.Children | Where-Object { $_.SchemaClassName -eq "Group" -and $_.Name -eq $g })) {
            New-Item -Path "C:\FTP\$g" -ItemType Directory -Force | Out-Null
            $nuevoGrupo = $global:ADSI.Create("Group", $g)
            $nuevoGrupo.SetInfo()
            Write-Host "Grupo $g creado." -ForegroundColor Cyan
        }
    }
}

function Alta-NuevoUsuario {
    if ($null -eq $global:ADSI) { $global:ADSI = [ADSI]"WinNT://$env:COMPUTERNAME" }

    do {
        $global:NombreUserFTP = Read-Host "Nombre del nuevo alumno"
        if (Get-LocalUser -Name $global:NombreUserFTP -ErrorAction SilentlyContinue) {
            Write-Host "Error: El usuario ya existe." -ForegroundColor Red
        }
    } while (Get-LocalUser -Name $global:NombreUserFTP -ErrorAction SilentlyContinue)
    
    $global:ClaveFTP = Read-Host "Contraseña (ej. 1234)"
    $opcion = Read-Host "Grupo: 1 -> Reprobados | 2 -> Recursadores"
    $global:AsignacionGrupo = if ($opcion -eq "1") { "Reprobados" } else { "Recursadores" }

    # Crear cuenta
    $cuentaFTP = $global:ADSI.create("User", $global:NombreUserFTP)
    $cuentaFTP.SetInfo()    
    $cuentaFTP.SetPassword($global:ClaveFTP)    
    $cuentaFTP.SetInfo()    

    # Carpeta Personal y Links
    $rutaBase = "C:\FTP\LocalUser\$global:NombreUserFTP"
    if (-not(Test-Path $rutaBase)) {
        New-Item -Path "$rutaBase\$global:NombreUserFTP" -ItemType Directory -Force | Out-Null
        # mklink crea el "puente" para el aislamiento
        cmd /c mklink /D "$rutaBase\General" "C:\FTP\LocalUser\Public\General" | Out-Null
        cmd /c mklink /D "$rutaBase\$global:AsignacionGrupo" "C:\FTP\$global:AsignacionGrupo" | Out-Null
    }       
}

function Aplicar-SeguridadNTFS {
    # Añadir al grupo local
    Add-LocalGroupMember -Group $global:AsignacionGrupo -Member $global:NombreUserFTP -ErrorAction SilentlyContinue

    # 1. PERMISOS EN CARPETAS GRUPALES (MODIFICACIÓN)
    icacls "C:\FTP\Reprobados" /grant "Reprobados:(OI)(CI)M" /Q | Out-Null
    icacls "C:\FTP\Recursadores" /grant "Recursadores:(OI)(CI)M" /Q | Out-Null

    # 2. PERMISOS EN CARPETA GENERAL (TODOS MODIFICAN)
    # Otorgamos 'M' (Modify) a ambos grupos
    icacls "C:\FTP\LocalUser\Public\General" /grant "Usuarios:(OI)(CI)M" /Q | Out-Null
    
    # 3. PERMISO PARA "ATRAVESAR" LA CARPETA PUBLIC (Necesario para el Link)
    icacls "C:\FTP\LocalUser\Public" /grant "$($global:AsignacionGrupo):(RX)" /Q | Out-Null

    # 4. PERMISO TOTAL EN CARPETA PERSONAL
    icacls "C:\FTP\LocalUser\$global:NombreUserFTP" /grant:r "$($global:NombreUserFTP):(OI)(CI)M" /T /C /Q | Out-Null
}

function Mover-UsuarioDeGrupo {
    param([string]$TargetUser)
    
    # 1. Verificamos que el usuario exista
    if (-not (Get-LocalUser -Name $TargetUser -ErrorAction SilentlyContinue)) {
        Write-Host "Usuario no encontrado." -ForegroundColor Red ; return
    }

    # 2. Preguntamos el nuevo destino directamente para evitar ambigüedades
    Write-Host "`nSeleccione el NUEVO GRUPO para ${TargetUser}:"
    Write-Host "1) Reprobados"
    Write-Host "2) Recursadores"
    $opDestino = Read-Host "Elija destino"
    
    $grupoDestino = if ($opDestino -eq "1") { "Reprobados" } elseif ($opDestino -eq "2") { "Recursadores" } else { Write-Host "Opción inválida." -ForegroundColor Red; return }

    # 3. Lo quitamos de AMBOS grupos para evitar historiales fantasma
    Remove-LocalGroupMember -Group "Reprobados" -Member $TargetUser -ErrorAction SilentlyContinue
    Remove-LocalGroupMember -Group "Recursadores" -Member $TargetUser -ErrorAction SilentlyContinue
    
    # 4. Lo añadimos al nuevo grupo
    Add-LocalGroupMember -Group $grupoDestino -Member $TargetUser -ErrorAction SilentlyContinue
    
    # 5. Borramos TODOS los links anteriores que pudieran existir
    $baseUser = "C:\FTP\LocalUser\$TargetUser"
    cmd /c rmdir "$baseUser\Reprobados" 2>nul
    cmd /c rmdir "$baseUser\Recursadores" 2>nul
    
    # 6. Creamos el link nuevo
    cmd /c mklink /D "$baseUser\$grupoDestino" "C:\FTP\$grupoDestino" | Out-Null
    
    # 7. EL TRUCO ESTRELLA: Reiniciamos el FTP para borrar la memoria caché de IIS
    Restart-Service ftpsvc -ErrorAction SilentlyContinue
    
    Write-Host "`n¡Éxito! $TargetUser ha sido movido a $grupoDestino y los accesos viejos se borraron." -ForegroundColor Green
}

# ==========================================
# MENÚ PRINCIPAL
# ==========================================
$global:ADSI = [ADSI]"WinNT://$env:ComputerName"

do {
    Clear-Host
    Write-Host "=============================" -ForegroundColor Cyan
    Write-Host "   PANEL ADMINISTRATIVO FTP" -ForegroundColor Cyan
    Write-Host "============================="
    Write-Host "1) CONFIGURAR SERVIDOR (Instalacion)"
    Write-Host "2) ALTA MASIVA DE USUARIOS"
    Write-Host "3) CAMBIAR ALUMNO DE GRUPO"
    Write-Host "4) SALIR DEL SISTEMA"
    Write-Host "-----------------------------"
    
    $seleccion = Read-Host "Elija el numero de la accion"

    switch ($seleccion) {
        "1" {
            Preparar-ServidorFTP
            Generar-GruposClase
            Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
            Set-ItemProperty "IIS:\Sites\FTP" -Name ftpServer.security.ssl.dataChannelPolicy -Value 0
            Restart-WebItem "IIS:\Sites\FTP"
            Write-Host "Proceso de instalacion finalizado." -ForegroundColor Green
            Pause
        }
        "2" {
            $cantidadUsuarios = Read-Host "¿Cuantos usuarios desea crear en esta sesion?"
            
            if ($cantidadUsuarios -as [int] -and [int]$cantidadUsuarios -gt 0) {
                for ($i = 1; $i -le [int]$cantidadUsuarios; $i++) {
                    Write-Host "`n--- Creando Alumno $i de $cantidadUsuarios ---" -ForegroundColor Yellow
                    Alta-NuevoUsuario
                    Aplicar-SeguridadNTFS
                    Write-Host "Usuario guardado." -ForegroundColor Green
                }
            } else {
                Write-Host "Cantidad no valida." -ForegroundColor Red
            }
            Pause
        }
        "3" {
            $nomAlumno = Read-Host "Ingrese el login del usuario a reubicar"
            Mover-UsuarioDeGrupo -TargetUser $nomAlumno
            Pause
        }
        "4" {
            Write-Host "Cerrando script..." -ForegroundColor Yellow
        }
        default {
            Write-Host "La opcion $seleccion no es valida." -ForegroundColor Red
            Pause
        }
    }
} while ($seleccion -ne "4")