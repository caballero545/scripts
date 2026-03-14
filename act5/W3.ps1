$FTP="C:\FTP"

Write-Host "Aplicando permisos base..."

icacls $FTP /inheritance:r

icacls $FTP /grant "Administrators:(OI)(CI)F"
icacls $FTP /grant "SYSTEM:(OI)(CI)F"
icacls $FTP /grant "IIS_IUSRS:(OI)(CI)RX"
icacls $FTP /grant "Users:(RX)"

Write-Host "Permisos carpetas publicas..."

icacls "C:\FTP\general" /grant "ftpusers:(OI)(CI)M"

Write-Host "Permisos carpetas de grupo..."

icacls "C:\FTP\usuarios\reprobados" /grant "reprobados:(OI)(CI)M"
icacls "C:\FTP\usuarios\recursadores" /grant "recursadores:(OI)(CI)M"

Write-Host "Permisos vhome (necesarios para IIS)..."

icacls "C:\FTP\vhome" /grant "Users:(RX)"
icacls "C:\FTP\vhome\LocalUser" /grant "Users:(RX)"
icacls "C:\FTP\vhome\LocalUser" /grant "ftpusers:(OI)(CI)RX"
icacls "C:\FTP\vhome" /grant "ftpusers:(RX)"


Import-Module WebAdministration

Clear-WebConfiguration `
-Filter "system.ftpServer/security/authorization" `
-PSPath "IIS:\" `
-Location "FTP"

# permitir lectura a todos
Add-WebConfiguration `
-Filter "system.ftpServer/security/authorization" `
-PSPath "IIS:\" `
-Location "FTP" `
-Value @{accessType="Allow";users="*";permissions="Read"}

# permitir lectura y escritura al grupo ftpusers
Add-WebConfiguration `
-Filter "system.ftpServer/security/authorization" `
-PSPath "IIS:\" `
-Location "FTP" `
-Value @{accessType="Allow";roles="ftpusers";permissions="Read,Write"}

# Crear la sección SSL en el sitio FTP
Add-WebConfiguration `
-PSPath "IIS:\" `
-Location "FTP" `
-Filter "system.ftpServer/security" `
-Value @{ssl=@{controlChannelPolicy="SslAllow";dataChannelPolicy="SslAllow"}}

# Reiniciar el servicio FTP
Restart-Service ftpsvc

# Verificar configuración
Get-WebConfiguration `
-Filter "system.ftpServer/security/authorization" `
-PSPath "IIS:\" `
-Location "FTP"

Write-Host "Permisos aplicados correctamente."