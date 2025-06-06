#!/bin/bash

# Script: diagnostico-proxmox.sh
# Autor: OpenAI + VIPs (adaptado e expandido)
# Descrição: Diagnóstico avançado e contínuo do ambiente Proxmox VE
# Requisitos: smartmontools, iproute2, net-tools, curl, dig, ss

#============================================================#
# CONFIGURAÇÕES INICIAIS
#============================================================#
set -euo pipefail
DATA=$(date '+%Y-%m-%d_%H-%M-%S')
NOME=$(hostname)
LOGFILE="/tmp/diagnostico-proxmox_${NOME}_${DATA}.log"

exec > >(tee -a "$LOGFILE") 2>&1

echo "🔎 Iniciando Diagnóstico Avançado - $DATA - Nó: $NOME"
echo "Arquivo de log: $LOGFILE"
echo "--------------------------------------------------------"

#============================================================#
# 1. VERIFICAR CONECTIVIDADE EXTERNA
#============================================================#
echo -e "\n🌐 Testando conectividade com gateway e internet..."
ping -c 3 172.20.220.1 >/dev/null && echo "✅ Gateway OK" || echo "❌ Gateway inacessível"
ping -c 3 8.8.8.8 >/dev/null && echo "✅ Google DNS OK" || echo "❌ Sem acesso à internet (IP)"

#============================================================#
# 2. RESOLUÇÃO DNS E PTR
#============================================================#
echo -e "\n🔎 Verificando DNS e resolução reversa..."
which dig >/dev/null || apt install -y dnsutils >/dev/null
HOSTIP=$(hostname -I | awk '{print $1}')
dig +short google.com >/dev/null && echo "✅ DNS direto OK" || echo "❌ Falha DNS direto"
PTR=$(dig +short -x $HOSTIP)
[[ -z "$PTR" ]] && echo "⚠️  Sem PTR configurado para $HOSTIP" || echo "✅ PTR OK: $PTR"

#============================================================#
# 3. INTERFACES, MTU E GATEWAY
#============================================================#
echo -e "\n📡 Verificando interfaces e rotas..."
ip a
ip r

#============================================================#
# 4. VERIFICAÇÃO DE FIREWALL ATIVO
#============================================================#
echo -e "\n🛡️  Verificando regras de firewall ativas (iptables)..."
iptables -S || echo "❌ iptables não disponível"
ip6tables -S || echo "❌ ip6tables não disponível"
pve-firewall compile >/dev/null && echo "✅ Regras do Proxmox válidas" || echo "❌ Erro de sintaxe nas regras do Proxmox"

#============================================================#
# 5. CONECTIVIDADE ENTRE NÓS (Cluster)
#============================================================#
echo -e "\n🔁 Verificando conectividade entre nós do cluster..."
NODES=$(pvecm nodes | awk '/^[ 0-9]/ {print $2}')
for NODE in $NODES; do
    echo -n "↔️  Ping para $NODE: "; ping -c 2 $NODE >/dev/null && echo "OK" || echo "❌ Falha"
    for PORT in 22 8006 5404 5405; do
        timeout 2 bash -c ": </dev/tcp/$NODE/$PORT" 2>/dev/null && echo "   ✅ Porta $PORT aberta em $NODE" || echo "   ❌ Porta $PORT bloqueada em $NODE"
    done
    echo
done

#============================================================#
# 6. SERVIÇOS ESSENCIAIS
#============================================================#
echo -e "\n⚙️  Verificando serviços do Proxmox..."
SERVICOS=(corosync pve-cluster pvedaemon pvestatd pveproxy)
for SVC in "${SERVICOS[@]}"; do
  systemctl is-active --quiet $SVC && echo "✅ $SVC ativo" || echo "❌ $SVC inativo"
  systemctl status $SVC --no-pager | grep -E 'Active:|Loaded:'
done

#============================================================#
# 7. DISCOS, SMART E ZFS
#============================================================#
echo -e "\n💾 Verificando discos e ZFS..."
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
for DISK in $(ls /dev/sd? /dev/nvme?n1 2>/dev/null); do
    echo "SMART: $DISK"; smartctl -H $DISK | grep -i result || echo "⚠️  Falha ao ler SMART de $DISK"
done
zpool status || echo "ℹ️  Nenhum pool ZFS detectado"

#============================================================#
# 8. USO DE MEMÓRIA, CPU E LOAD
#============================================================#
echo -e "\n📊 Verificando uso de recursos..."
free -h
uptime

#============================================================#
# 9. LOGS RECENTES DO SISTEMA
#============================================================#
echo -e "\n🪵 Logs recentes com erros/avisos:"
journalctl -p 3 -xb | tail -n 30

echo -e "\n🪵 Logs do kernel relevantes:"
dmesg --level=err,warn | tail -n 30

#============================================================#
# 10. SUGESTÕES DE AÇÃO
#============================================================#
echo -e "\n💡 Sugestões baseadas em resultado parcial:"
[[ -z "$PTR" ]] && echo "➡️  Configure PTR reverso para $HOSTIP (entrada DNS tipo PTR)" || true
echo "➡️  Verifique regras iptables ou firewall caso bloqueio em portas entre nós"
echo "➡️  Revise serviços inativos (se listados) com 'systemctl restart nome'"
echo "➡️  Execute 'apt update && apt full-upgrade' caso necessário"
echo "➡️  Faça backup do log gerado: $LOGFILE"

echo -e "\n✅ Diagnóstico finalizado às $(date '+%Y-%m-%d %H:%M:%S')"
