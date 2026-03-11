$FTP="C:\FTP"

icacls $FTP /inheritance:r

icacls $FTP /grant "Administrators:(OI)(CI)F"
icacls $FTP /grant "IIS_IUSRS:(OI)(CI)RX"
icacls $FTP /grant "Users:(RX)"

icacls "C:\FTP\general" /grant "ftpusers:(OI)(CI)M"

icacls "C:\FTP\usuarios\reprobados" /grant "reprobados:(OI)(CI)M"
icacls "C:\FTP\usuarios\recursadores" /grant "recursadores:(OI)(CI)M"