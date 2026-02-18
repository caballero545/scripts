#!/bin/bash
echo "----estatus se cambio el coso?----"
echo "nombre del equipo: $(hostname)"
echo "ip actual: $(ip -4 addr show | grep -v '127.0.0.1' | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | head -n 1)"
echo "espacio en disco: "
df -h / | grep /