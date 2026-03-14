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

Write-Host "Permisos vhome..."

icacls "C:\FTP\vhome" /grant "Users:(RX)"
icacls "C:\FTP\vhome" /grant "ftpusers:(RX)"

icacls "C:\FTP\vhome\LocalUser" /grant "Users:(RX)"
icacls "C:\FTP\vhome\LocalUser" /grant "ftpusers:(OI)(CI)RX"

Import-Module WebAdministration

Clear-WebConfiguration `
-Filter "system.ftpServer/security/authorization" `
-PSPath "IIS:\" `
-Location "FTP"

Add-WebConfiguration `
-Filter "system.ftpServer/security/authorization" `
-PSPath "IIS:\" `
-Location "FTP" `
-Value @{accessType="Allow";users="*";permissions="Read"}

Add-WebConfiguration `
-Filter "system.ftpServer/security/authorization" `
-PSPath "IIS:\" `
-Location "FTP" `
-Value @{accessType="Allow";roles="ftpusers";permissions="Read,Write"}

Set-WebConfigurationProperty `
-Filter "system.ftpServer/security/ssl" `
-PSPath "IIS:\" `
-Location "FTP" `
-Name controlChannelPolicy `
-Value SslAllow

Set-WebConfigurationProperty `
-Filter "system.ftpServer/security/ssl" `
-PSPath "IIS:\" `
-Location "FTP" `
-Name dataChannelPolicy `
-Value SslAllow

Restart-Service ftpsvc

Write-Host "Permisos aplicados correctamente"