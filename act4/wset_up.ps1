Write-Host "--- PREPARANDO WINDOWS SERVER PARA ADMINISTRACIÓN REMOTA ---" -ForegroundColor Cyan

# 1. Instalar OpenSSH Server (Equivalente al apt install openssh-server)
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# 2. Iniciar y habilitar SSH y WinRM
Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'
Enable-PSRemoting -Force

# 3. Configurar contraseña (No es común por script, pero validamos el usuario)
Write-Host "Asegúrate de que el usuario '$env:USERNAME' tenga contraseña establecida." -ForegroundColor Yellow

# 4. Mostrar IP
$ip = (Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Ethernet*").IPAddress[0]
Write-Host "--- LISTO ---" -ForegroundColor Green
Write-Host "IP del servidor Windows: $ip"