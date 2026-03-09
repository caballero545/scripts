Write-Host "===== CONFIGURANDO FTP ====="

Install-WindowsFeature Web-Server
Install-WindowsFeature Web-FTP-Server
Install-WindowsFeature Web-FTP-Service

New-LocalGroup reprobados -ErrorAction SilentlyContinue
New-LocalGroup recursadores -ErrorAction SilentlyContinue
New-LocalGroup ftpusers -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Path C:\FTP -Force
New-Item -ItemType Directory -Path C:\FTP\general -Force
New-Item -ItemType Directory -Path C:\FTP\usuarios\reprobados -Force
New-Item -ItemType Directory -Path C:\FTP\usuarios\recursadores -Force
New-Item -ItemType Directory -Path C:\FTP\vhome -Force

Write-Host "FTP instalado."