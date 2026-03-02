Write-Host "--- PREPARANDO WINDOWS SERVER PARA ADMINISTRACIÓN REMOTA ---" -ForegroundColor Cyan

# 1. Instalar OpenSSH Server

Add-WindowsCapability -Online -Name OpenSSH.Server

# 2. Iniciar y habilitar SSH y WinRM
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
Enable-PSRemoting -Force

# 3. Validación de usuario
Write-Host "Asegúrate de que el usuario '$env:USERNAME' tenga contraseña establecida." -ForegroundColor Yellow

# 4. Mostrar IP
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -like "Ethernet*"}).IPAddress | Select-Object -First 1

Write-Host "--- LISTO ---"