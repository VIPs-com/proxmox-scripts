#!/bin/bash
# Script de verificação de rede para Proxmox VE - Versão 1.3

echo "ℹ️  Verificação de rede iniciada em $(date '+%Y-%m-%d %H:%M:%S')"

# 1. Verificar dependências essenciais
for cmd in ping ip awk timeout nslookup nc curl; do
  if ! command -v $cmd &>/dev/null; then
    echo "❌ ERRO: Comando '$cmd' não encontrado! Instale-o antes de continuar."
    exit 1
  fi
done

# 2. Teste de conectividade com o gateway
GATEWAY=$(ip route show default | awk '/default/ {print $3}')
echo -e "\n🔍 Testando conectividade com gateway ($GATEWAY)..."
if ping -c 4 "$GATEWAY" &>/dev/null; then
  echo "✅ Gateway acessível"
else
  echo "❌ Problema de conectividade com o gateway"
fi

# 3. Verificação de resolução DNS
echo -e "\n🌍 Testando resolução DNS..."
if nslookup google.com &>/dev/null; then
  echo "✅ Resolução de nomes funcionando"
else
  echo "❌ Problema na resolução DNS"
fi

# 4. Exibir IPs locais
echo -e "\n🌐 Endereços de rede locais:"
ip -brief address show | grep -v 'lo'

# 5. Teste de portas essenciais
echo -e "\n🔌 Verificando portas críticas..."
for porta in 22 8006 5404 5405; do
  nc -zv localhost $porta &>/dev/null && \
    echo "✅ Porta $porta acessível" || \
    echo "❌ Porta $porta fechada ou inacessível"
done

# 6. Teste de comunicação entre nós do cluster
echo -e "\n📡 Testando comunicação com outros nós..."
for ip in 172.20.220.21 172.20.220.22; do
  ping -c 2 $ip >/dev/null && \
    echo "✅ Nó $ip acessível" || \
    echo "❌ Nó $ip inacessível"
done

# 7. Teste de velocidade da rede
echo -e "\n🚀 Testando velocidade da rede..."
curl -s https://speed.hetzner.de/100MB.bin -o /dev/null --write-out "✅ Download concluído - Velocidade: %{speed_download} bytes/s\n"

# 8. Verificação de conectividade externa
SERVERS="google.com cloudflare.com github.com"
echo -e "\n🌍 Testando conectividade com servidores externos..."
for server in $SERVERS; do
  ping -c 2 $server &>/dev/null && echo "✅ Conectado a $server" || echo "❌ Não foi possível alcançar $server"
done

# 9. Verificação de firewall
echo -e "\n🛡️  Verificando regras de firewall..."
sudo ufw status
sudo iptables -L -n | grep DROP

# 10. Teste de conectividade SSH entre nós
echo -e "\n🔄 Testando conectividade SSH entre nós..."
for ip in 172.20.220.20 172.20.220.21; do
  nc -zvw3 $ip 22 && echo "✅ SSH ativo em $ip" || echo "❌ SSH inacessível em $ip"
done

# 11. Teste de perda de pacotes
echo -e "\n📊 Testando perda de pacotes..."
ping -c 10 8.8.8.8 | grep 'packet loss'

# 12. Exibir resumo final
echo -e "\n📝 Resumo Final:"
echo "--------------------------------"
echo "ℹ️  Diagnóstico concluído!"
echo "--------------------------------"

exit 0