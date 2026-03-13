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

Set-WebConfigurationProperty `
-Filter "system.ftpServer/security/ssl" `
-Name controlChannelPolicy `
-Value SslAllow `
-PSPath "IIS:\Sites\FTP"

Set-WebConfigurationProperty `
-Filter "system.ftpServer/security/ssl" `
-Name dataChannelPolicy `
-Value SslAllow `
-PSPath "IIS:\Sites\FTP"

Restart-Service ftpsvc

Get-WebConfigurationProperty `
-Filter "system.ftpServer/security/ssl" `
-PSPath "IIS:\Sites\FTP" `
-Name "*"

Write-Host "Permisos aplicados correctamente."