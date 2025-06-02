#!/bin/bash
# Script de verificação de rede para Proxmox VE - Versão 1.8

echo "ℹ️  Verificação de rede iniciada em $(date '+%Y-%m-%d %H:%M:%S')"

# 1. Verificação de permissões de root
if [[ $EUID -ne 0 ]]; then
  echo "❌ Este script deve ser executado como root!"
  exit 1
fi

# 2. Configuração dinâmica de IPs
CLUSTER_IPS="172.20.220.21 172.20.220.22"
EXTERNAL_SERVERS="google.com cloudflare.com github.com"

# 3. Atualizar lista de pacotes e instalar dependências essenciais
echo -e "\n🔧 Verificando e instalando pacotes essenciais..."
DEPENDENCIAS="curl wget net-tools dnsutils nc"
for pkg in $DEPENDENCIAS; do
  if ! dpkg -l | grep -q "$pkg"; then
    echo "📦 Instalando $pkg..."
    apt-get update &>/dev/null
    apt-get install -y $pkg &>/dev/null
    echo "✅ $pkg instalado!"
  else
    echo "✅ $pkg já está instalado!"
  fi
done

echo "==========================="
echo "📡 Teste de conectividade"
echo "==========================="

# 4. Teste de conectividade com o gateway
GATEWAY=$(ip route show default | awk '/default/ {print $3}')
echo -e "\n🔍 Testando conectividade com gateway ($GATEWAY)..."
if ping -c 4 "$GATEWAY" &>/dev/null; then
  echo "✅ Gateway acessível"
else
  echo "❌ Problema de conectividade com o gateway"
  logger "Falha na conexão com o gateway $GATEWAY"
fi

# 5. Verificação de resolução DNS
echo -e "\n🌍 Testando resolução DNS..."
if nslookup google.com &>/dev/null; then
  echo "✅ Resolução de nomes funcionando"
else
  echo "❌ Problema na resolução DNS"
  logger "Falha na resolução de DNS"
fi

echo "==========================="
echo "🌐 Teste de Rede Local"
echo "==========================="

# 6. Exibir IPs locais
echo -e "\n🌐 Endereços de rede locais:"
ip -brief address show | grep -v 'lo'

# 7. Identificação detalhada de interfaces de rede DOWN
echo -e "\n⚠️ Verificando interfaces de rede..."
ip -brief link show | awk '$3 == "DOWN" {print "⚠️ Interface", $1, "está desligada! Verifique a conexão."}'

# 8. Teste de portas essenciais
echo -e "\n🔌 Verificando portas críticas..."
for porta in 22 8006 5404 5405; do
  if nc -zv localhost $porta &>/dev/null; then
    echo "✅ Porta $porta acessível"
  else
    echo "❌ Porta $porta fechada! Verifique o firewall com: ufw allow $porta/tcp"
    logger "Falha na conexão pela porta $porta"
  fi
done

# 9. Teste de comunicação entre nós do cluster
echo -e "\n📡 Testando comunicação com outros nós..."
for ip in $CLUSTER_IPS; do
  ping -c 2 $ip >/dev/null && \
    echo "✅ Nó $ip acessível" || \
    echo "❌ Nó $ip inacessível"
    logger "Falha na comunicação com o nó $ip"
done

echo "==========================="
echo "🔄 Testes Adicionais"
echo "==========================="

# 10. Teste de conectividade com servidores externos
echo -e "\n🌍 Testando conectividade com servidores externos..."
for server in $EXTERNAL_SERVERS; do
  ping -c 2 $server &>/dev/null && echo "✅ Conectado a $server" || echo "❌ Não foi possível alcançar $server"
  logger "Falha ao conectar-se ao servidor externo $server"
done

# 11. Teste de conectividade SSH entre nós
echo -e "\n🔄 Testando conectividade SSH entre nós..."
for ip in $CLUSTER_IPS; do
  nc -zvw3 $ip 22 && echo "✅ SSH ativo em $ip" || echo "❌ SSH inacessível em $ip"
  logger "Falha na conexão SSH com o nó $ip"
done

# 12. Teste de perda de pacotes
echo -e "\n📊 Testando perda de pacotes..."
ping -c 10 8.8.8.8 | grep 'packet loss'

echo "==========================="
echo "📝 Resumo Final"
echo "==========================="
echo "ℹ️  Diagnóstico concluído!"
echo "==========================="

exit 0