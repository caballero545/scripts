# --- FUNCIÓN 1: INSTALAR/VERIFICAR ROL DHCP ---
function Download-Update-DHCP {
    Write-Host "--- Verificando Rol DHCP ---" -ForegroundColor Cyan
    $check = Get-WindowsFeature -Name DHCP
    if ($check.Installed -eq $false) {
        Write-Host "Instalando Rol DHCP..."
        Install-WindowsFeature -Name DHCP -IncludeManagementTools
    } else {
        Write-Host "El Rol DHCP ya está instalado."
    }
    Read-Host "Presiona [Enter] para volver al menú..."
}
# --- FUNCIÓN 2: CONFIGURAR PARÁMETROS ---
function Configure-DHCP-Range {
    
}

# --- FUNCIÓN 3: APLICAR EN WINDOWS SERVER ---
function Apply-DHCP-Config {
    try {
        # 1. Configurar IP Estática en el Servidor
        $interface = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
        $ip_srv = "$SEGMENTO.1"
        
        Write-Host "Configurando IP $ip_srv en $($interface.Name)..."
        New-NetIPAddress -InterfaceAlias $interface.Name -IPAddress $ip_srv -PrefixLength 24 -ErrorAction SilentlyContinue

        # 2. Crear el Ámbito (Scope) en el DHCP
        Add-DhcpServerv4Scope -Name "Red_Automatizada" -StartRange $IP_INI -EndRange $IP_FIN -SubnetMask 255.255.255.0 -LeaseDuration $LEASE_TIME
        
        # 3. Opciones de Gateway y DNS
        if ($GATEWAY) { Set-DhcpServerv4OptionValue -OptionId 3 -Value $GATEWAY }
        if ($DNS_SRV) { Set-DhcpServerv4OptionValue -OptionId 6 -Value $DNS_SRV }

        Write-Host "¡SERVIDOR DHCP ACTIVO Y CONFIGURADO!" -ForegroundColor Green
    } catch {
        Write-Host "Error al aplicar: $($_.Exception.Message)" -ForegroundColor Red
    }
    Read-Host "Presiona [Enter] para volver..."
}

# --- FUNCIÓN 4: MONITOREAR ---
function Monitor-DHCP {
    Clear-Host
    Write-Host "=== ESTADO DEL SERVIDOR DHCP ===" -ForegroundColor Cyan
    Get-Service -Name DHCPServer | Select-Object Status, DisplayName
    Write-Host "`n--- Concesiones Activas (Clientes) ---"
    if ($SEGMENTO) {
        Get-DhcpServerv4Lease -ScopeId "$SEGMENTO.0" -ErrorAction SilentlyContinue
    } else {
        Write-Host "No se ha configurado ningún segmento aún."
    }
    Read-Host "`nPresiona [Enter] para volver..."
}

# --- MENÚ PRINCIPAL ---
while($true) {
    Clear-Host
    Write-Host "------------------------------------------"
    Write-Host "   MENU DE ADMINISTRACION DHCP (WINDOWS)"
    Write-Host "------------------------------------------"
    Write-Host "1. Instalar Rol DHCP"
    Write-Host "2. Configurar y Activar Ámbito"
    Write-Host "3. Monitorear Clientes"
    Write-Host "4. Salir"
    
    $op = Read-Host "Seleccione una opción"
    switch ($op) {
        "1" { Download-Update-DHCP }
        "2" { Configure-DHCP-Range }
        "3" { Monitor-DHCP }
        "4" { exit }
        default { Write-Host "Opción inválida." }
    }
}