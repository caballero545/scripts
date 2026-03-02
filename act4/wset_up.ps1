Write-Host "--- PREPARANDO WINDOWS SERVER PARA ADMINISTRACION REMOTA ---" -ForegroundColor Cyan

# 1. Instalar OpenSSH Server (Corregido el nombre del capability)
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# 2. Iniciar y habilitar SSH y WinRM
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
Enable-PSRemoting -Force

# 3. Abrir puerto en el Firewall (Importante para que tu física lo vea)
New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -DisplayName "OpenSSH Server (sshd)" -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -ErrorAction SilentlyContinue

# 4. Obtención de IP robusta
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127*" }).IPAddress | Select-Object -First 1

Write-Host "--- LISTO ---" -ForegroundColor Green
Write-Host "IP del servidor Windows: $ip"
Write-Host "Intenta conectar desde tu PC con: ssh $env:USERNAME@$ip"