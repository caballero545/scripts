#!/bin/bash

BASE="/srv/ftp/usuarios"
VHOME="/srv/ftp/vhome"

echo "=============================="
echo "      ELIMINAR USUARIO FTP"
echo "=============================="

echo ""
echo "Usuarios FTP existentes:"
echo "------------------------"
# Listamos los usuarios basándonos en sus carpetas personales
find "$VHOME" -maxdepth 1 -mindepth 1 -type d -printf "%f\n"

echo ""
read -p "Escribe el nombre del usuario a eliminar: " usuario

# Verificar si existe en el sistema
if ! id "$usuario" &>/dev/null; then
    echo "Ese usuario no existe."
    read -p "Presiona ENTER para continuar..."
    exit
fi

# Detectar a qué grupo pertenece antes de borrarlo para poder desmontar
grupo=$(id -gn "$usuario")

echo ""
echo "Desmontando carpetas compartidas de $usuario..."

# 1. DESMONTAJE DE SEGURIDAD (Crítico)
# Usamos -l (lazy) para asegurar que se suelte aunque FileZilla esté conectado
umount -l "$VHOME/$usuario/general" 2>/dev/null
umount -l "$VHOME/$usuario/$grupo" 2>/dev/null

# 2. LIMPIEZA DE FSTAB
# Borramos las líneas de este usuario en fstab para que no intenten montarse al reiniciar
sed -i "/\/vhome\/$usuario\//d" /etc/fstab

echo "Eliminando usuario y archivos personales..."

# 3. ELIMINACIÓN DEL USUARIO
# userdel -r intenta borrar el home del sistema, pero como usamos VHOME personalizado, 
# forzamos la limpieza manual de las carpetas físicas.
userdel -f "$usuario" 2>/dev/null

# 4. BORRADO FÍSICO SEGURO
# Ahora que está desmontado, el rm -rf solo borrará la carpeta vacía y el contenido personal
rm -rf "$BASE/reprobados/$usuario" 2>/dev/null
rm -rf "$BASE/recursadores/$usuario" 2>/dev/null
rm -rf "$VHOME/$usuario"

echo "Usuario $usuario eliminado correctamente."

echo ""
read -p "Presiona ENTER para continuar..."