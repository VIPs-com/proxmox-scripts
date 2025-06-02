#!/bin/bash
# Script de verificação de rede para Proxmox Cluster

echo "✅ Verificação de rede iniciada em $(date)"

# Teste de ping básico
echo -e "\n🔍 Testando conectividade básica:"
ping -c 4 8.8.8.8 | grep 'packet loss'

# Verifica IP local
echo -e "\n🌐 IP local:"
hostname -I

echo -e "\n✅ Verificação concluída!"
