#!/bin/bash
# verifica-rede.sh - Verificação completa de rede para clusters Proxmox

# Configurações
TIMEOUT=2
CLUSTER_PEER_IPS=("172.20.220.20" "172.20.220.21")
ESSENTIAL_PORTS=("22" "8006" "5404" "5405" "5406" "5407")

# Funções
log_info() { echo -e "ℹ️  $1"; }
log_success() { echo -e "✅ $1"; }
log_error() { echo -e "❌ $1"; }
test_port() { timeout $TIMEOUT bash -c "cat < /dev/null > /dev/tcp/$1/$2" 2>/dev/null; }

# Teste de Ping com Latência
test_latency() {
    local avg_ping=$(ping -c 4 -W $TIMEOUT $1 | grep rtt | awk -F'/' '{print $5}')
    if [ -z "$avg_ping" ]; then
        log_error "  $1 → Falha no ping"
    else
        log_success "  $1 → Latência média: ${avg_ping}ms"
    fi
}

# --- Execução ---
clear
log_info "🔍 Diagnóstico de Rede - $(date)"
echo "----------------------------------------"

# 1. Teste de Latência
log_info "1/3 - Medição de Latência:"
for ip in "${CLUSTER_PEER_IPS[@]}"; do
    test_latency $ip
done

# 2. Teste de Portas
log_info "\n2/3 - Verificando portas essenciais:"
for ip in "${CLUSTER_PEER_IPS[@]}"; do
    log_info "🔧 Nó $ip:"
    for port in "${ESSENTIAL_PORTS[@]}"; do
        if test_port $ip $port; then
            log_success "  Porta $port → Acessível"
        else
            log_error "  Porta $port → Bloqueada/Inacessível"
        fi
    done
done

# 3. Verificação DNS
log_info "\n3/3 - Verificando resolução DNS:"
for ip in "${CLUSTER_PEER_IPS[@]}"; do
    hostname=$(dig +short -x "$ip" 2>/dev/null | sed 's/\.$//')
    if [ -z "$hostname" ]; then
        log_error "  $ip → Sem resolução reversa"
    else
        log_success "  $ip → $hostname"
    fi
done

# Resumo
echo -e "\n📊 Resultado Final:"
if [ $? -eq 0 ]; then
    log_success "Todos os testes básicos passaram!"
    log_info "Recomendação: Prossiga com a instalação"
else
    log_error "Problemas detectados na configuração de rede"
    log_info "Recomendação: Resolva os itens em vermelho antes de continuar"
fi
echo "----------------------------------------"
