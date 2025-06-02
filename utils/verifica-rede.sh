#!/bin/bash
# Script de verificação de rede para Proxmox VE - Versão 2.2
# 🚀 Objetivo: Validar conectividade do cluster antes da pós-instalação

echo "ℹ️  Verificação de rede iniciada em $(date '+%Y-%m-%d %H:%M:%S')"
LOG_FILE="verifica-rede.log"

# 1️⃣ **Verificação de permissões de root**
if [[ $EUID -ne 0 ]]; then
  echo "❌ Este script deve ser executado como root!" | tee -a "$LOG_FILE"
  exit 1
fi

# 2️⃣ **Configuração dinâmica de IPs**
CLUSTER_IPS=("172.20.220.20" "172.20.220.21")
EXTERNAL_SERVERS=("google.com" "cloudflare.com" "github.com")

# 3️⃣ **Instalação de pacotes essenciais**
echo -e "\n🔧 Verificando pacotes..."
DEPENDENCIAS=("curl" "wget" "net-tools" "dnsutils" "nc")
for pkg in "${DEPENDENCIAS[@]}"; do
  if ! dpkg -l | grep -q "$pkg"; then
    echo "📦 Instalando $pkg..." | tee -a "$LOG_FILE"
    apt-get update &>/dev/null
    apt-get install -y "$pkg" &>/dev/null
    echo "✅ $pkg instalado!" | tee -a "$LOG_FILE"
  else
    echo "✅ $pkg já está instalado!" | tee -a "$LOG_FILE"
  fi
done

# 4️⃣ **Verificação de conectividade**
GATEWAY=$(ip route show default | awk '/default/ {print $3}')
echo -e "\n🔍 Testando conexão com gateway ($GATEWAY)..."
if ping -c 4 "$GATEWAY" &>/dev/null; then
  echo "✅ Gateway acessível" | tee -a "$LOG_FILE"
else
  echo "❌ Problema de conectividade com o gateway" | tee -a "$LOG_FILE"
fi

echo -e "\n🌍 Testando resolução DNS..."
if nslookup google.com &>/dev/null; then
  echo "✅ DNS funcionando" | tee -a "$LOG_FILE"
else
  echo "❌ Problema na resolução DNS" | tee -a "$LOG_FILE"
fi

# 5️⃣ **Verificação de interfaces de rede**
echo -e "\n🌐 Interfaces de rede:"
ip -brief address show | grep -v 'lo' | tee -a "$LOG_FILE"

echo -e "\n⚠️ Interfaces DOWN:"
ip -brief link show | awk '$3 == "DOWN" {print "⚠️", $1, "está desligada!"}' | tee -a "$LOG_FILE"

# 6️⃣ **Verificação de portas essenciais**
echo -e "\n🔌 Verificando portas críticas..."
for porta in 22 8006 5404 5405; do
  if nc -zv localhost "$porta" &>/dev/null; then
    echo "✅ Porta $porta acessível" | tee -a "$LOG_FILE"
  else
    echo "❌ Porta $porta fechada! Use: ufw allow $porta/tcp" | tee -a "$LOG_FILE"
  fi
done

# 7️⃣ **Testes entre nós do cluster**
echo -e "\n📡 Testando conectividade entre nós..."
for ip in "${CLUSTER_IPS[@]}"; do
  if ping -c 2 "$ip" >/dev/null; then
    echo "✅ Nó $ip acessível" | tee -a "$LOG_FILE"
  else
    echo "❌ Nó $ip inacessível" | tee -a "$LOG_FILE"
  fi
done

# 8️⃣ **Verificação do Firewall (UFW/IPTables)**
echo -e "\n🛡️ Status do Firewall:"
if command -v ufw &>/dev/null; then
  ufw status | grep -q "active" && echo "✅ UFW ativo!" | tee -a "$LOG_FILE" || echo "⚠️ UFW inativo!" | tee -a "$LOG_FILE"
else
  echo "⚠️ UFW não encontrado, verificando IPTables..." | tee -a "$LOG_FILE"
fi
iptables -L -n | grep DROP | tee -a "$LOG_FILE"

# 9️⃣ **Teste de conectividade externa**
echo -e "\n🌍 Testando conexão externa..."
for server in "${EXTERNAL_SERVERS[@]}"; do
  if ping -c 2 "$server" &>/dev/null; then
    echo "✅ Conectado a $server" | tee -a "$LOG_FILE"
  else
    echo "❌ Não alcançado: $server" | tee -a "$LOG_FILE"
  fi
done

# 🔟 **Teste de conectividade SSH entre nós**
echo -e "\n🔄 Teste SSH entre nós..."
for ip in "${CLUSTER_IPS[@]}"; do
  if nc -zvw3 "$ip" 22; then
    echo "✅ SSH ativo em $ip" | tee -a "$LOG_FILE"
  else
    echo "❌ SSH inacessível em $ip" | tee -a "$LOG_FILE"
  fi
done

# 1️⃣1️⃣ **Teste de perda de pacotes**
echo -e "\n📊 Testando perda de pacotes..."
ping -c 10 8.8.8.8 | grep 'packet loss' | tee -a "$LOG_FILE"

# ✅ **Resumo Final**
echo -e "\n✅ Diagnóstico concluído!" | tee -a "$LOG_FILE"
echo "📄 Log salvo em: $LOG_FILE"

# 🔔 **Aviso Final**
echo -e "\n🔔 **Todas as verificações foram concluídas!**"
echo "📌 Se tudo estiver funcionando corretamente, agora execute o script de pós-instalação!"
echo "🔹 Comando: bash /caminho/do/script-postinstall.sh"
echo "🔹 Isso garantirá que seu cluster Proxmox esteja totalmente configurado e otimizado."