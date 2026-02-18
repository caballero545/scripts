#!/bin/bash
echo "----estatus se cambio el coso?----"
echo "nombre del equipo: $(hostname)"
echo "ip actual: $(ip addr show enp0s8 | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)"d/ -f1 | head -n 1)"
echo "espacio en disco: "
df -h / | grep /