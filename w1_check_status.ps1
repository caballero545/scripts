# Mostrar encabezado
Write-Host "--- REPORTE DE WINDOWS ---" -ForegroundColor Cyan

# Obtener nombre del equipo
Write-Host "Nombre del equipo: $env:COMPUTERNAME"

# Obtener IP de la red interna (Ethernet 2)
$ip = (Get-NetIPAddress -InterfaceAlias "Ethernet 2" -AddressFamily IPv4).IPAddress
Write-Host "IP actual: $ip"

# Mostrar espacio en disco C
Write-Host "Espacio en disco C:"
Get-PSDrive C | Select-Object Free, Used