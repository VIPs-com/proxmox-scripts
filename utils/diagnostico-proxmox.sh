#!/bin/bash

# Script: diagnostico-proxmox.sh
# Autor: OpenAI + VIPs (refinado)
# Descrição: Diagnóstico avançado e contínuo do ambiente Proxmox VE
# Requisitos: smartmontools, iproute2, net-tools, curl, dig, ss, zfsutils-linux

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
# FUNÇÕES AUXILIARES
#============================================================#
verificar_comando() {
  command -v "$1" >/dev/null || echo "⚠️  Comando '$1' não encontrado. Instale-o com: apt install -y $2"
}

#============================================================#
# 1. CONECTIVIDADE EXTERNA
#============================================================#
echo -e "\n🌐 Testando conectividade com gateway e internet..."
ping -c 3 172.20.220.1 >/dev/null && echo "✅ Gateway OK" || echo "❌ Gateway inacessível"
ping -c 3 8.8.8.8 >/dev/null && echo "✅ Google DNS OK" || echo "❌ Sem acesso à internet (IP)"

#============================================================#
# 2. RESOLUÇÃO DNS E PTR
#============================================================#
echo -e "\n🔎 Verificando DNS e resolução reversa..."
verificar_comando dig dnsutils
HOSTIP=$(hostname -I | awk '{print $1}')
dig +short google.com >/dev/null && echo "✅ DNS direto OK" || echo "❌ Falha DNS direto"
PTR=$(dig +short -x "$HOSTIP")
[[ -z "$PTR" ]] && echo "⚠️  Sem PTR configurado para $HOSTIP" || echo "✅ PTR OK: $PTR"

#============================================================#
# 3. INTERFACES, MTU E GATEWAY
#============================================================#
echo -e "\n📡 Verificando interfaces e rotas..."
verificar_comando ip iproute2
ip a
ip r

#============================================================#
# 4. FIREWALL E REGRAS
#============================================================#
echo -e "\n🛡️  Verificando regras de firewall ativas (iptables)..."
verificar_comando iptables iptables
verificar_comando ip6tables iptables
verificar_comando pve-firewall pve-firewall
iptables -S || echo "❌ iptables não disponível"
ip6tables -S || echo "❌ ip6tables não disponível"
pve-firewall compile >/dev/null && echo "✅ Regras do Proxmox válidas" || echo "❌ Erro de sintaxe nas regras do Proxmox"

#============================================================#
# 5. CONECTIVIDADE ENTRE NÓS DO CLUSTER
#============================================================#
echo -e "\n🔁 Verificando conectividade entre nós do cluster..."
verificar_comando pvecm proxmox-cluster
NODES=$(pvecm nodes | awk '/^[ 0-9]/ {print $2}')
for NODE in $NODES; do
    printf "↔️  %-15s : " "$NODE"
    ping -c 2 "$NODE" >/dev/null && echo "OK" || echo "❌ Falha"
    for PORT in 22 8006 5404 5405; do
        timeout 2 bash -c ": </dev/tcp/$NODE/$PORT" 2>/dev/null && echo "   ✅ Porta $PORT aberta" || echo "   ❌ Porta $PORT bloqueada"
    done
    echo
done

#============================================================#
# 6. SERVIÇOS ESSENCIAIS DO PROXMOX
#============================================================#
echo -e "\n⚙️  Verificando serviços do Proxmox..."
SERVICOS=(corosync pve-cluster pvedaemon pvestatd pveproxy)
for SVC in "${SERVICOS[@]}"; do
  systemctl is-active --quiet "$SVC" && echo "✅ $SVC ativo" || echo "❌ $SVC inativo"
  systemctl status "$SVC" --no-pager | grep -E 'Active:|Loaded:|fail|error' || true
done

#============================================================#
# 7. DISCOS, SMART E ZFS
#============================================================#
echo -e "\n💾 Verificando discos e ZFS..."
verificar_comando smartctl smartmontools
verificar_comando lsblk util-linux
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT
for DISK in $(ls /dev/sd? /dev/nvme?n1 2>/dev/null); do
    echo "SMART: $DISK"; smartctl -H "$DISK" | grep -i result || echo "⚠️  Falha ao ler SMART de $DISK"
done
verificar_comando zpool zfsutils-linux
zpool status || echo "ℹ️  Nenhum pool ZFS detectado"

#============================================================#
# 8. USO DE MEMÓRIA, CPU E CARGA
#============================================================#
echo -e "\n📊 Verificando uso de recursos..."
free -h
uptime

#============================================================#
# 9. LOGS RECENTES DO SISTEMA
#============================================================#
echo -e "\n🪵 Logs recentes com erros/avisos do journalctl:"
journalctl -p 3 -n 50 --no-pager || echo "ℹ️  Nenhum log crítico recente encontrado."

echo -e "\n🪵 Logs do kernel (dmesg):"
dmesg --level=err,warn | tail -n 30 || echo "ℹ️  Nenhum aviso crítico recente no kernel"

#============================================================#
# 10. SUGESTÕES DE AÇÃO
#============================================================#
echo -e "\n💡 Sugestões baseadas nos resultados:"
[[ -z "$PTR" ]] && echo "➡️  Configure PTR reverso para $HOSTIP (entrada DNS tipo PTR)"
echo "➡️  Verifique bloqueios de porta no firewall entre nós (5404/5405 UDP, 22/8006 TCP)"
echo "➡️  Revise serviços inativos com: systemctl restart <serviço>"
echo "➡️  Atualize pacotes se necessário: apt update && apt full-upgrade"
echo "➡️  Faça backup do log gerado: $LOGFILE"

echo -e "\n✅ Diagnóstico finalizado às $(date '+%Y-%m-%d %H:%M:%S')"
