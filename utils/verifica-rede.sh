#!/usr/bin/env bash
# verifica-ambiente-proxmox.sh - Script para diagnosticar ambiente (rede e serviços) do Proxmox VE 8xx
# Autor: VIPs-com
# Versão: 1.v2.0
# Data: 2025-06-02
#
# Uso:
#   Execute diretamente: ./verifica-ambiente-proxmox.sh
#   Modo silencioso (apenas status de saída): ./verifica-ambiente-proxmox.sh -s
#   Verificar versão: ./verifica-ambiente-proxmox.sh --version
#   Com IPs/Portas personalizados via variáveis de ambiente (use vírgula):
#     CLUSTER_PEER_IPS="172.20.220.20,172.20.220.21" ESSENTIAL_PORTS="22,8006" ./verifica-ambiente-proxmox.sh

# ========== Configurações Padrão ==========
TIMEOUT=2 # Timeout para comandos de rede em segundos
# IPs de peers do cluster Proxmox (use para testes de latência/portas entre nós)
CLUSTER_PEER_IPS=("172.20.220.20" "172.20.220.21")
# IPs essenciais para conectividade geral (ex: gateway, DNS públicos como 8.8.8.8)
GENERAL_CONNECTIVITY_IPS=("172.20.220.1" "8.8.8.8")
# Portas TCP essenciais do Proxmox e SSH.
ESSENTIAL_PORTS=("22" "8006" "5404" "5405" "5406" "5407")
# Interface de rede principal do Proxmox (geralmente vmbr0)
PROXMOX_BRIDGE_INTERFACE="vmbr0"
# Host para teste de resolução DNS
DNS_TEST_HOST="google.com"
# Serviços essenciais do Proxmox VE
PROXMOX_SERVICES=("corosync" "pve-cluster" "pvedaemon" "pvestatd" "pveproxy")

# Sobrescreve IPs e portas padrão se as variáveis de ambiente estiverem definidas.
[[ -n "$CLUSTER_IPS" ]] && IFS=',' read -r -a CLUSTER_PEER_IPS <<< "$CLUSTER_IPS"
[[ -n "$PORTS" ]] && IFS=',' read -r -a ESSENTIAL_PORTS <<< "$PORTS"

# ========== Configuração de Logs ==========
LOG_DIR="/var/log/verifica-proxmox" # Nova pasta de logs para este script.
mkdir -p "$LOG_DIR" # Cria a pasta se não existir.
LOG_FILE="$LOG_DIR/diagnostico-$(date +%Y%m%d-%H%M%S).log" # Log com data e hora para cada execução.
LOG_RETENTION_DAYS=15 # Dias para manter os logs antes da limpeza automática.

# ========== Estado do Script ==========
EXIT_STATUS=0 # Variável para controlar o status de saída final (0 = sucesso, 1 = falha).

# ========== Funções de Log e Saída ==========
# Códigos de cores ANSI para uma saída visualmente agradável no terminal.
VERMELHO='\033[0;31m'
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
CIANO='\033[0;36m'
ROXO='\033[0;35m'
SEM_COR='\033[0m' # Reseta a cor para o padrão do terminal.

# Controle de verbosidade: por padrão, o script é 'verbose' (exibe tudo na tela).
# Se o primeiro argumento for '-s' ou '--silent', desativa a saída detalhada para o terminal.
VERBOSE=true
if [[ "$1" == "-s" || "$1" == "--silent" ]]; then
    VERBOSE=false
    shift # Remove o argumento de modo silencioso para não interferir em outros argumentos.
fi

# Argumento para exibir a versão do script.
if [[ "$1" == "--version" ]]; then
    echo "verifica-ambiente-proxmox.sh v1.0.0"
    exit 0
fi

# Configuração de redirecionamento de saída para log e terminal (stdout/stderr).
# Isso garante que a saída vá para o log e, se VERBOSE, também para o terminal com cores.
exec 3>&1        # Salva o descritor de arquivo padrão para stdout (1) no descritor 3.
exec &>> "$LOG_FILE" # Redireciona todas as saídas (stdout e stderr) para o arquivo de log (append).
if [ "$VERBOSE" = true ]; then
    exec 1>&3    # Se o modo VERBOSE estiver ativo, restaura o stdout para o terminal.
fi

# Funções de log com cores e controle de verbosidade.
log_cabecalho() { echo -e "\n${ROXO}=== $1 ===${SEM_COR}"; }
log_info()    { echo -e "ℹ️  ${CIANO}$@${SEM_COR}"; }
log_success() { echo -e "✅ ${VERDE}$@${SEM_COR}"; }
log_error()   { echo -e "❌ ${VERMELHO}$@${SEM_COR}"; EXIT_STATUS=1; } # Erros sempre são exibidos e definem o status de saída para falha.
log_aviso()   { echo -e "⚠️  ${AMARELO}$@${SEM_COR}"; }


# ========== Funções de Teste e Validação ==========
# is_valid_ipv4: Valida o formato de um endereço IPv4.
is_valid_ipv4() {
    local ip=$1
    # Verifica o formato geral xxx.xxx.xxx.xxx
    [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
    # Verifica se cada octeto está entre 0 e 255.
    local IFS=. # Define o delimitador interno de campo para '.'
    local i
    for i in $ip; do
        [[ "$i" -lt 0 || "$i" -gt 255 ]] && return 1
    done
    return 0
}

# test_port_connectivity: Tenta conectar a uma porta TCP remota.
test_port_connectivity() {
    local ip=$1
    local port=$2
    timeout "$TIMEOUT" bash -c "cat < /dev/null > /dev/tcp/$ip/$port" 2>/dev/null
}

# test_ping_latency: Realiza testes de ping e mede a latência.
test_ping_latency() {
    local ip=$1
    local avg_ping
    # Ping 4 pacotes com um timeout, extrai a latência média.
    avg_ping=$(ping -c 4 -W "$TIMEOUT" "$ip" | awk -F'/' '/rtt/ {print $5}')
    if [[ -z "$avg_ping" ]]; then
        log_error "  $ip → Falha no ping ou timeout."
    else
        log_success "  $ip → Latência média: ${avg_ping}ms."
    fi
}

# check_mtu: Verifica o MTU da interface de rede principal do Proxmox.
check_mtu() {
    local optimal_mtu=1500 # MTU ideal para a maioria das redes Gigabit Ethernet.
    local current_mtu=$(ip link show "$PROXMOX_BRIDGE_INTERFACE" 2>/dev/null | awk '/mtu/ {print $5; exit}')
    if [[ -z "$current_mtu" ]]; then
        log_aviso "Não foi possível determinar o MTU da interface '$PROXMOX_BRIDGE_INTERFACE'. Verifique o nome da interface."
    elif [[ "$current_mtu" -lt "$optimal_mtu" ]]; then
        log_aviso "MTU da interface '$PROXMOX_BRIDGE_INTERFACE' é ${current_mtu} (Recomendado: ${optimal_mtu}). Pode haver fragmentação de pacotes."
    else
        log_success "MTU da interface '$PROXMOX_BRIDGE_INTERFACE' é ${current_mtu} (OK)."
    fi
}

# check_service_status: Verifica se um serviço systemd está ativo.
check_service_status() {
    local service_name=$1
    systemctl is-active --quiet "$service_name"
    if [[ $? -eq 0 ]]; then
        log_success "Serviço '$service_name' está ativo."
    else
        log_error "Serviço '$service_name' NÃO está ativo."
    fi
}


# ========== Checagem de Dependências Essenciais ==========
log_cabecalho "Verificando Dependências Essenciais do Sistema"
REQUIRED_COMMANDS=("ping" "dig" "timeout" "ip" "ss" "systemctl")
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Dependência ausente: '$cmd' não encontrado. Instale-a (ex: 'apt install -y iputils-ping dnsutils coreutils iproute2 systemd')."
        exit 1 # Aborta o script se uma dependência crítica estiver faltando.
    else
        log_success "'$cmd' encontrado."
    fi
done

# ========== Validação Inicial das Configurações do Script ==========
log_cabecalho "Validando Configurações do Script"
# Valida IPs de peers (para comunicação entre nós do cluster)
if [[ ${#CLUSTER_PEER_IPS[@]} -eq 0 ]]; then
    log_aviso "Nenhum IP de peer configurado em CLUSTER_PEER_IPS. Testes de comunicação entre nós serão pulados."
else
    for ip in "${CLUSTER_PEER_IPS[@]}"; do
        if ! is_valid_ipv4 "$ip"; then
            log_error "IP inválido configurado em CLUSTER_PEER_IPS: '$ip'. Por favor, corrija."
            EXIT_STATUS=1
        else
            log_success "IP de peer configurado: $ip (válido)."
        fi
    done
fi

# Valida IPs de conectividade geral (para internet/gateway)
if [[ ${#GENERAL_CONNECTIVITY_IPS[@]} -eq 0 ]]; then
    log_aviso "Nenhum IP de conectividade geral configurado. Testes de ping básicos serão pulados."
else
    for ip in "${GENERAL_CONNECTIVITY_IPS[@]}"; do
        if ! is_valid_ipv4 "$ip"; then
            log_error "IP inválido configurado em GENERAL_CONNECTIVITY_IPS: '$ip'. Por favor, corrija."
            EXIT_STATUS=1
        else
            log_success "IP de conectividade geral: $ip (válido)."
        fi
    done
fi

# Valida Portas Essenciais
if [[ ${#ESSENTIAL_PORTS[@]} -eq 0 ]]; then
    log_aviso "Nenhuma porta essencial configurada em ESSENTIAL_PORTS. Testes de portas serão pulados."
else
    for port in "${ESSENTIAL_PORTS[@]}"; do
        # Verifica se a porta é um número e está no intervalo válido (1-65535).
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
            log_error "Porta inválida configurada em ESSENTIAL_PORTS: '$port'. Por favor, corrija."
            EXIT_STATUS=1
        else
            log_success "Porta essencial configurada: $port (válida)."
        fi
    done
fi

# Se houver erros de validação inicial, o script aborta aqui para evitar problemas nos testes.
[[ $EXIT_STATUS -ne 0 ]] && { log_error "Por favor, corrija as configurações e execute novamente."; exit 1; }

# ========== Execução dos Testes de Ambiente ==========
clear # Limpa a tela para uma saída limpa no terminal (não afeta o arquivo de log).
log_info "🔍 Iniciando Diagnóstico de Ambiente para Proxmox VE - $(date)."
log_info "IP local deste nó: $(hostname -I | awk '{print $1}')"
echo "----------------------------------------"

# 1. Verificação de Conectividade Geral (Internet/Gateway)
log_cabecalho "1/5 - Verificando Conectividade Geral (Internet/Gateway)"
if [[ ${#GENERAL_CONNECTIVITY_IPS[@]} -eq 0 ]]; then
    log_aviso "Testes de conectividade geral pulados (Nenhum IP configurado em GENERAL_CONNECTIVITY_IPS)."
else
    for ip in "${GENERAL_CONNECTIVITY_IPS[@]}"; do
        test_ping_latency "$ip"
    done
fi

# 2. Teste de Resolução DNS
log_cabecalho "2/5 - Testando Resolução DNS"
nslookup "$DNS_TEST_HOST" &> /dev/null
if [[ $? -eq 0 ]]; then
    log_success "Resolução DNS funcionando para '$DNS_TEST_HOST'."
else
    log_error "Falha na resolução DNS para '$DNS_TEST_HOST'."
fi

# 3. Verificação de Interface de Rede e MTU
log_cabecalho "3/5 - Verificação de Interface de Rede e MTU"
ip addr show "$PROXMOX_BRIDGE_INTERFACE" &> /dev/null
if [[ $? -eq 0 ]]; then
    log_success "Interface '$PROXMOX_BRIDGE_INTERFACE' existe."
    IP_ATRIBUIDO=$(ip -4 addr show "$PROXMOX_BRIDGE_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [[ -n "$IP_ATRIBUIDO" ]]; then
        log_info "IP atribuído à '$PROXMOX_BRIDGE_INTERFACE': $IP_ATRIBUIDO."
    else
        log_aviso "Interface '$PROXMOX_BRIDGE_INTERFACE' não tem IP IPv4 atribuído."
    fi
    check_mtu
else
    log_error "Interface '$PROXMOX_BRIDGE_INTERFACE' NÃO encontrada."
fi

# 4. Testes de Latência e Portas entre Nós do Cluster
log_cabecalho "4/5 - Testes de Latência e Portas (Comunicação de Cluster)"
if [[ ${#CLUSTER_PEER_IPS[@]} -eq 0 ]]; then
    log_aviso "Testes de latência e portas entre nós pulados (Nenhum IP de peer configurado em CLUSTER_PEER_IPS)."
else
    log_info "Medição de Latência para Nós do Cluster:"
    for ip in "${CLUSTER_PEER_IPS[@]}"; do
        test_ping_latency "$ip"
    done

    log_info "Verificando Portas Essenciais nos Nós do Cluster:"
    if [[ ${#ESSENTIAL_PORTS[@]} -eq 0 ]]; then
        log_aviso "Nenhuma porta essencial configurada. Testes de portas pulados."
    else
        for ip in "${CLUSTER_PEER_IPS[@]}"; do
            log_info "🔧 Nó $ip:"
            for port in "${ESSENTIAL_PORTS[@]}"; do
                if test_port_connectivity "$ip" "$port"; then
                    log_success "  Porta $port → Acessível."
                else
                    log_error "  Porta $port → Bloqueada/Inacessível."
                fi
            done
        done
    fi
fi

# 5. Verificação dos Serviços Essenciais do Proxmox VE
log_cabecalho "5/5 - Verificando Serviços Essenciais do Proxmox VE"
for servico in "${PROXMOX_SERVICES[@]}"; do
    check_service_status "$servico"
done

# ========== Resumo Final ==========
echo -e "\n📊 Resultado Final do Diagnóstico:"
if [[ $EXIT_STATUS -eq 0 ]]; then
    log_success "DIAGNÓSTICO CONCLUÍDO SEM ERROS! O ambiente está pronto para o Proxmox VE."
    log_info "Recomendação: Prossiga com a instalação ou configuração principal do Proxmox."
else
    log_error "DIAGNÓSTICO CONCLUÍDO COM PROBLEMAS! Por favor, revise os itens marcados com ❌."
    log_info "Recomendação: Resolva os problemas antes de prosseguir com a instalação do Proxmox VE."
fi
echo "----------------------------------------"

# ========== Limpeza de Logs Antigos ==========
log_info "Realizando limpeza de logs antigos na pasta '$LOG_DIR' (mantendo os últimos $LOG_RETENTION_DAYS dias)..."
find "$LOG_DIR" -type f -name "diagnostico-*.log" -mtime +"$LOG_RETENTION_DAYS" -delete
log_success "Limpeza de logs concluída."

exit "$EXIT_STATUS" # O script sai com 0 para sucesso ou 1 para falha, útil para automação.