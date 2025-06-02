#!/bin/bash
# Script de verificação de rede para Proxmox VE
# Versão: 1.0
# Uso: bash <(curl -s https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/utils/verifica-rede.sh)

echo "ℹ️  Verificação de rede iniciada em $(date '+%Y-%m-%d %H:%M:%S')"

# 1. Teste de conectividade básica
echo -e "\n🔍 Testando conectividade com gateway..."
ping -c 4 $(ip route show default | awk '/default/ {print $3}') | grep 'packet loss'

# 2. Verificação de IP local
echo -e "\n🌐 Endereços de rede locais:"
ip -brief address show | grep -v 'lo'

# 3. Teste de portas essenciais
echo -e "\n🔌 Verificando portas críticas..."
for porta in 22 8006 5404 5405; do
  timeout 1 bash -c "echo >/dev/tcp/localhost/$porta" 2>/dev/null &&
    echo "✅ Porta $porta aberta" || echo "❌ Porta $porta fechada"

# 4. Adicione no final do script
echo -e "\n📡 Testando comunicação com outros nós..."
for ip in 172.20.220.20 172.20.220.21; do
  ping -c 2 $ip >/dev/null && 
    echo "✅ Nó $ip acessível" || echo "❌ Nó $ip inacessível"
done

echo -e "\n✅ Verificação concluída com sucesso!"
