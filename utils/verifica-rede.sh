#!/bin/bash
# Script de verificação de rede para Proxmox VE - Versão 1.9

echo "ℹ️  Verificação de rede iniciada em $(date '+%Y-%m-%d %H:%M:%S')"
LOG_FILE="verifica-rede.log"

# 1. Verificação de permissões de root
if [[ $EUID -ne 0 ]]; then
  echo "❌ Este script deve ser executado como root!" | tee -a "$LOG_FILE"
  exit 1
fi

# 2. Configuração dinâmica de IPs
CLUSTER_IPS="172.20.220.20 172.20.220.21"
EXTERNAL_SERVERS="google.com cloudflare.com github.com"

# 3. Atualizar lista de pacotes e instalar dependências essenciais
echo -e "\n🔧 Verificando pacotes essenciais..."
DEPENDENCIAS="curl wget net-tools dnsutils nc"
for pkg in $DEPENDENCIAS; do
  if ! dpkg -l | grep -q "$pkg"; then
    echo "📦 Instalando $pkg..." | tee -a "$LOG_FILE"
    apt-get update &>/dev/null
    apt-get install -y $pkg &>/dev/null
    echo "✅ $pkg instalado!" | tee -a "$LOG_FILE"
  else
    echo "✅ $pkg já está instalado!" | tee -a "$LOG_FILE"
  fi
done

# 4. Teste de conectividade com o gateway
GATEWAY=$(ip route show default | awk '/default/ {print $3}')
echo -e "\n🔍 Testando conexão com gateway ($GATEWAY)..."
if ping -c 4 "$GATEWAY" &>/dev/null; then
  echo "✅ Gateway acessível" | tee -a "$LOG_FILE"
else
  echo "❌ Problema de conectividade com o gateway" | tee -a "$LOG_FILE"
fi

# 5. Verificação de resolução DNS
echo -e "\n🌍 Testando resolução DNS..."
if nslookup google.com &>/dev/null; then
  echo "✅ DNS funcionando" | tee -a "$LOG_FILE"
else
  echo "❌ Problema na resolução DNS" | tee -a "$LOG_FILE"
fi

# 6. Verificação de interfaces de rede
echo -e "\n🌐 Interfaces de rede:"
ip -brief address show | grep -v 'lo' | tee -a "$LOG_FILE"

# 7. Identificação de interfaces desligadas
echo -e "\n⚠️ Interfaces DOWN:"
ip -brief link show | awk '$3 == "DOWN" {print "⚠️", $1, "está desligada!"}' | tee -a "$LOG_FILE"

# 8. Teste de portas essenciais
echo -e "\n🔌 Verificando portas críticas..."
for porta in 22 8006 5404 5405; do
  if nc -zv localhost $porta &>/dev/null; then
    echo "✅ Porta $porta acessível" | tee -a "$LOG_FILE"
  else
    echo "❌ Porta $porta fechada! Use: ufw allow $porta/tcp" | tee -a "$LOG_FILE"
  fi
done

# 9. Teste de comunicação entre nós do cluster
echo -e "\n📡 Testando conectividade entre nós..."
for ip in $CLUSTER_IPS; do
  ping -c 2 $ip >/dev/null && echo "✅ Nó $ip acessível" || echo "❌ Nó $ip inacessível"
  tee -a "$LOG_FILE"
done

# 10. Teste de firewall (UFW e IPTables)
echo -e "\n🛡️ Status do Firewall:"
if command -v ufw &>/dev/null; then
  ufw status | grep -q "active" && echo "✅ UFW ativo!" || echo "⚠️ UFW instalado, mas inativo!"
else
  echo "⚠️ UFW não encontrado! O firewall pode ser gerenciado por outra solução."
fi
iptables -L -n | grep DROP | tee -a "$LOG_FILE"

# 11. Teste de conectividade com servidores externos
echo -e "\n🌍 Conectividade externa:"
for server in $EXTERNAL_SERVERS; do
  ping -c 2 $server &>/dev/null && echo "✅ Conectado a $server" || echo "❌ Não alcançado: $server"
  tee -a "$LOG_FILE"
done

# 12. Teste de conectividade SSH entre nós
echo -e "\n🔄 Teste SSH entre nós..."
for ip in $CLUSTER_IPS; do
  nc -zvw3 $ip 22 && echo "✅ SSH ativo em $ip" || echo "❌ SSH inacessível em $ip"
  tee -a "$LOG_FILE"
done

# 13. Teste de perda de pacotes
echo -e "\n📊 Testando perda de pacotes..."
ping -c 10 8.8.8.8 | grep 'packet loss' | tee -a "$LOG_FILE"

# 14. Exibir resumo final
echo -e "\n✅ Diagnóstico concluído!" | tee -a "$LOG_FILE"
echo "📄 Log salvo em: $LOG_FILE"

exit 0