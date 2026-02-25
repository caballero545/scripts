# main_win.ps1
. .\dns_functions.ps1 # Equivalente al 'source' de Bash

$IP_FIJA = ""
$SEGMENTO = ""
$OCT_SRV = ""

while ($true) {
    Clear-Host
    Write-Host "=== ADMIN WINDOWS SERVER (IP: $($IP_FIJA -ne "" ? $IP_FIJA : "PENDIENTE")) ===" -ForegroundColor Yellow
    Write-Host "1. Instalar Todo       2. IP Fija"
    Write-Host "3. Configurar DHCP     4. Añadir Dominio"
    Write-Host "5. Eliminar Dominio    6. Listar Dominios"
    Write-Host "7. Status              8. Salir"
    
    $op = Read-Host "Seleccione"

    switch ($op) {
        "1" { Instalar-Servicios }
        "2" { 
            $res = Establecer-IPFija-Logic
            if ($res -ne "ERROR") {
                $IP_FIJA = $res
                $parts = $IP_FIJA.Split('.')
                $SEGMENTO = "$($parts[0]).$($parts[1]).$($parts[2])"
                $OCT_SRV = $parts[3]
            }
        }
        "3" { Config-DHCP-Logic $IP_FIJA $SEGMENTO $OCT_SRV }
        "4" {
            if ($IP_FIJA -eq "") { Write-Host "Fije IP primero"; Start-Sleep 2; continue }
            $dom = Read-Host "Nombre dominio"
            $status = Add-Dominio-Logic $dom $IP_FIJA
            if ($status -eq 0) { Write-Host "Éxito" -ForegroundColor Green } else { Write-Host "Error o existe" -ForegroundColor Red }
            Start-Sleep 2
        }
        "5" {
            $domDel = Read-Host "Dominio a borrar"
            if ((Del-Dominio-Logic $domDel) -eq 0) { Write-Host "Borrado" } else { Write-Host "No existe" }
            Start-Sleep 2
        }
        "6" { Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false } | Select-Object ZoneName; Read-Host "Enter..." }
        "7" { Check-Status-Logic $IP_FIJA }
        "8" { exit }
    }
}