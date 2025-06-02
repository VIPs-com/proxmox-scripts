#!/usr/bin/env bash
# verifica-rede.sh - Verificação completa de rede para clusters Proxmox VE
# Autor: VIPs-com
# Versão: 1.1.0

# ========== Configurações Padrão ==========
TIMEOUT=2
CLUSTER_PEER_IPS=("172.20.220.20" "172.20.220.21")
ESSENTIAL_PORTS=("22" "8006" "5404" "5405" "5406" "5407")

[[ -n "$CLUSTER_IPS" ]] && IFS=',' read -ra CLUSTER_PEER_IPS <<< "$CLUSTER_IPS"
[[ -n "$PORTS" ]] && IFS=',' read -ra ESSENTIAL_PORTS <<< "$PORTS"

LOG_DIR="/var/log/verifica-rede"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/verifica-rede-$(date +%Y%m%d-%H%M%S).log"
LOG_RETENTION_DAYS=15
EXIT_STATUS=0

# ========== Cores ==========
VERMELHO='\033[0;31m'
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
CIANO='\033[0;36m'
ROXO='\033[0;35m'
SEM_COR='\033[0m'

# ========== Verbosidade ==========
VERBOSE=true
if [[ "$1" == "-s" || "$1" == "--silent" ]]; then
    VERBOSE=false
    shift
fi
if [[ "$1" == "--version" ]]; then
    echo "verifica-rede.sh v1.0.0"
    exit 0
fi

exec 3>&1
exec &>> "$LOG_FILE"
if [ "$VERBOSE" = true ]; then
    exec 1>&3
fi

# ========== Funções ==========
log_cabecalho() { echo -e "\n${ROXO}=== $1 ===${SEM_COR}"; }
log_info()    { echo -e "ℹ️  ${CIANO}$@${SEM_COR}"; }
log_success() { echo -e "✅ ${VERDE}$@${SEM_COR}"; }
log_error()   { echo -e "❌ ${VERMELHO}$@${SEM_COR}"; EXIT_STATUS=1; }
log_aviso()   { echo -e "⚠️  ${AMARELO}$@${SEM_COR}"; }

is_valid_ipv4() {
    local ip=$1
    [[ "$ip" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
    IFS=. read -r o1 o2 o3 o4 <<< "$ip"
    for o in $o1 $o2 $o3 $o4; do [[ "$o" -gt 255 ]] && return 1; done
    return 0
}

test_port() {
    timeout "$TIMEOUT" bash -c "cat < /dev/null > /dev/tcp/$1/$2" 2>/dev/null
}

test_latency() {
    local ip=$1
    local avg_ping
    avg_ping=$(ping -c 4 -W "$TIMEOUT" "$ip" | awk -F'/' '/rtt/ {print $5}')
    if [[ -z "$avg_ping" ]]; then
        log_error "  $ip → Falha no ping ou timeout."
    else
        log_success "  $ip → Latência média: ${avg_ping}ms."
    fi
}

test_mtu() {
    local optimal_mtu=1500
    local current_mtu
    current_mtu=$(ip link show | awk '/mtu/ {print $5; exit}')
    if [[ -z "$current_mtu" ]]; then
        log_aviso "Não foi possível determinar o MTU."
    elif [[ "$current_mtu" -lt "$optimal_mtu" ]]; then
        log_aviso "MTU detectado: ${current_mtu} (Recomendado: ${optimal_mtu})."
    else
        log_success "MTU detectado: ${current_mtu} (OK)."
    fi
}

test_dns() {
    local host="google.com"
    if dig +short "$host" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        log_success "Resolução DNS funcionando para '$host'."
    else
        log_error "Falha na resolução DNS para '$host'."
    fi
}

test_conexao_externa() {
    if ping -c 2 -W "$TIMEOUT" 8.8.8.8 > /dev/null; then
        log_success "Conectividade externa (8.8.8.8) OK."
    else
        log_error "Sem conectividade externa para 8.8.8.8."
    fi
}

# ========== Execução ==========
clear

log_cabecalho "🧰 Verificando Dependências"
for cmd in ping dig timeout ip; do
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Comando ausente: $cmd"
        exit 1
    else
        log_success "Comando encontrado: $cmd"
    fi
done

log_cabecalho "🌐 Validando IPs e Portas"
for ip in "${CLUSTER_PEER_IPS[@]}"; do
    is_valid_ipv4 "$ip" && log_success "IP válido: $ip" || log_error "IP inválido: $ip"
done

for port in "${ESSENTIAL_PORTS[@]}"; do
    [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]] \
        && log_success "Porta válida: $port" \
        || log_error "Porta inválida: $port"
done

[[ $EXIT_STATUS -ne 0 ]] && { log_error "Corrija erros acima antes de continuar."; exit 1; }

log_cabecalho "📡 Teste de MTU"
test_mtu

log_cabecalho "🌍 Testando Conectividade com IPs do Cluster"
for ip in "${CLUSTER_PEER_IPS[@]}"; do
    log_info "Ping para $ip"
    test_latency "$ip"
done

log_cabecalho "🚪 Testando Portas Essenciais"
for ip in "${CLUSTER_PEER_IPS[@]}"; do
    for port in "${ESSENTIAL_PORTS[@]}"; do
        if test_port "$ip" "$port"; then
            log_success "  $ip:$port → Acessível"
        else
            log_error "  $ip:$port → Bloqueado ou inativo"
        fi
    done
done

log_cabecalho "🧭 Testes de DNS e Conectividade"
test_dns
test_conexao_externa

log_cabecalho "🧹 Limpando Logs Antigos"
find "$LOG_DIR" -type f -name "*.log" -mtime +$LOG_RETENTION_DAYS -delete && log_success "Logs com mais de $LOG_RETENTION_DAYS dias removidos."

log_cabecalho "✅ Finalizado"
[[ $EXIT_STATUS -eq 0 ]] && log_success "Todos os testes concluídos com sucesso!" || log_error "Alguns testes falharam. Verifique o log: $LOG_FILE"

exit $EXIT_STATUS
