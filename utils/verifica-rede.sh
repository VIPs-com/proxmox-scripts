#!/usr/bin/env bash
# verifica-rede.sh - Verificação completa de rede para clusters Proxmox VE
# Autor: VIPs-com
# Versão: 1.0.0
# Uso:
#   Execute diretamente: ./verifica-rede.sh
#   Modo silencioso (apenas status de saída): ./verifica-rede.sh -s
#   Verificar versão: ./verifica-rede.sh --version
#   Com IPs/Portas personalizados via variáveis de ambiente:
#     CLUSTER_IPS="ip1,ip2" PORTS="port1,port2" ./verifica-rede.sh
#   Exemplo: CLUSTER_IPS="172.20.220.20,172.20.220.21" PORTS="22,8006" ./utils/verifica-rede.sh

# ========== Configurações Padrão ==========
TIMEOUT=2 # Timeout para comandos de rede em segundos
# IPs padrão dos seus nós de cluster (adicione ou remova conforme sua necessidade)
CLUSTER_PEER_IPS=("172.20.220.20" "172.20.220.21")
# Portas essenciais do Proxmox e SSH (adicione ou remova conforme sua necessidade)
ESSENTIAL_PORTS=("22" "8006" "5404" "5405" "5406" "5407")

# Sobrescreve IPs e portas padrão se as variáveis de ambiente CLUSTER_IPS ou PORTS estiverem definidas.
# Isso permite rodar o script com configurações diferentes sem editar o arquivo.
[[ -n "$CLUSTER_IPS" ]] && IFS=',' read -ra CLUSTER_PEER_IPS <<< "$CLUSTER_IPS"
[[ -n "$PORTS" ]] && IFS=',' read -ra ESSENTIAL_PORTS <<< "$PORTS"

# ========== Configuração de Logs ==========
LOG_DIR="/var/log/verifica-rede"
mkdir -p "$LOG_DIR" # Garante que o diretório de logs exista.
# Nome do arquivo de log, incluindo data e hora para garantir que seja único a cada execução.
LOG_FILE="$LOG_DIR/verifica-rede-$(date +%Y%m%d-%H%M%S).log"
LOG_RETENTION_DAYS=15 # Quantos dias de logs serão mantidos.

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
    echo "verifica-rede.sh v1.0.0" # Atualize a versão aqui para grandes mudanças.
    exit 0
fi

# Configuração de redirecionamento de saída para log e terminal (stdout/stderr).
# 1. Salva o descritor de arquivo padrão para stdout (1) no descritor 3.
# 2. Redireciona todas as saídas (stdout e stderr) para o arquivo de log.
# 3. Se o modo VERBOSE estiver ativo, restaura a saída do stdout para o terminal, duplicando a saída.
exec 3>&1        # Salva o stdout original no fd 3.
exec &>> "$LOG_FILE" # Redireciona stdout e stderr para o arquivo de log (append).
if [ "$VERBOSE" = true ]; then
    exec 1>&3    # Se VERBOSE for true, redireciona stdout de volta para o terminal.
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

# test_port: Tenta conectar a uma porta TCP para verificar acessibilidade.
test_port() {
    timeout "$TIMEOUT" bash -c "cat < /dev/null > /dev/tcp/$1/$2" 2>/dev/null
}

# test_latency: Realiza testes de ping e mede a latência média.
test_latency() {
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

# test_mtu: Verifica o MTU da interface de rede principal.
test_mtu() {
    local optimal_mtu=1500 # MTU ideal para a maioria das redes Gigabit Ethernet.
    # Obtém o MTU da primeira interface de rede listada (geralmente a principal).
    local current_mtu=$(ip link show | awk '/mtu/ {print $5; exit}')
    if [[ -z "$current_mtu" ]]; then
        log_aviso "Não foi possível determinar o MTU. Verifique as interfaces de rede."
    elif [[ "$current_mtu" -lt "$optimal_mtu" ]]; then
        log_aviso "MTU detectado: ${current_mtu} (Recomendado para rede gigabit: ${optimal_mtu}). Pode haver fragmentação de pacotes."
    else
        log_success "MTU detectado: ${current_mtu} (OK)."
    fi
}


# ========== Checagem de Dependências Essenciais ==========
log_cabecalho "Verificando Dependências Essenciais do Sistema"
REQUIRED_COMMANDS=("ping" "dig" "timeout" "ip") # Comandos necessários para os testes.
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Dependência ausente: '$cmd' não encontrado. Instale-o (ex: 'apt install -y iputils-ping dnsutils coreutils iproute2')."
        exit 1 # Aborta o script se uma dependência crítica estiver faltando.
    else
        log_success "'$cmd' encontrado."
    fi
done

# ========== Validação Inicial de IPs e Portas de Configuração ==========
log_cabecalho "Validando Configurações de IPs e Portas"
if [[ ${#CLUSTER_PEER_IPS[@]} -eq 0 ]]; then
    log_aviso "Nenhum IP de peer configurado em CLUSTER_PEER_IPS. Alguns testes de rede serão pulados."
else
    for ip in "${CLUSTER_PEER_IPS[@]}"; do
        if ! is_valid_ipv4 "$ip"; then
            log_error "IP inválido configurado em CLUSTER_PEER_IPS: '$ip'. Por favor, corrija."
            EXIT_STATUS=1 # Marca falha, mas continua verificando outros IPs.
        else
            log_success "IP de peer configurado: $ip (válido)."
        fi
    done
fi

if [[ ${#ESSENTIAL_PORTS[@]} -eq 0 ]]; then
    log_aviso "Nenhuma porta essencial configurada em ESSENTIAL_PORTS. Testes de portas serão pulados."
else
    for port in "${ESSENTIAL_PORTS[@]}"; do
        # Verifica se a porta é um número e está no intervalo válido (1-65535).
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
            log_error "Porta inválida configurada em ESSENTIAL_PORTS: '$port'. Por favor, corrija."
            EXIT_STATUS=1 # Marca falha, mas continua verificando outras portas.
        else
            log_success "Porta essencial configurada: $port (válida)."
        fi
    done
fi

# Se houver erros de validação inicial, o script aborta aqui.
[[ $EXIT_STATUS -ne 0 ]] && { log_error "Por favor, corrija as configurações de IPs/Portas e execute novamente."; exit 1; }

# ========== Execução dos Testes de Rede ==========
clear # Limpa a tela para uma saída limpa no terminal (não afeta o arquivo de log).
log_info "🔍 Iniciando Diagnóstico de Rede para Proxmox VE - $(date)."
log_info "IP local deste nó: $(hostname -I | awk '{print $1}')"
echo "----------------------------------------"

# 1. Teste de MTU
log_cabecalho "1/4 - Verificação de MTU"
test_mtu

# 2. Teste de Latência
log_cabecalho "2/4 - Medição de Latência para Nós do Cluster"
if [[ ${#CLUSTER_PEER_IPS[@]} -eq 0 ]]; then
    log_aviso "Teste de latência entre nós pulado (Nenhum IP de peer configurado)."
else
    for ip in "${CLUSTER_PEER_IPS[@]}"; do
        test_latency "$ip"
    done
fi

# 3. Teste de Portas
log_cabecalho "3/4 - Verificando Portas Essenciais nos Nós do Cluster"
if [[ ${#CLUSTER_PEER_IPS[@]} -eq 0 ]]; then
    log_aviso "Teste de portas pulado (Nenhum IP de peer configurado)."
elif [[ ${#ESSENTIAL_PORTS[@]} -eq 0 ]]; then
    log_aviso "Teste de portas pulado (Nenhuma porta essencial configurada)."
else
    for ip in "${CLUSTER_PEER_IPS[@]}"; do
        log_info "🔧 Nó $ip:"
        for port in "${ESSENTIAL_PORTS[@]}"; do
            if test_port "$ip" "$port"; then
                log_success "  Porta $port → Acessível."
            else
                log_error "  Porta $port → Bloqueada/Inacessível."
            fi
        done
    done
fi

# 4. Verificação DNS Reversa
log_cabecalho "4/4 - Verificando Resolução DNS Reversa"
if [[ ${#CLUSTER_PEER_IPS[@]} -eq 0 ]]; then
    log_aviso "Teste de DNS reverso pulado (Nenhum IP de peer configurado)."
else
    for ip in "${CLUSTER_PEER_IPS[@]}"; do
        hostname=$(dig +short -x "$ip" 2>/dev/null | sed 's/\.$//')
        if [[ -z "$hostname" ]]; then
            log_error "  $ip → Sem resolução DNS reversa."
        else
            log_success "  $ip → $hostname (resolução reversa OK)."
        fi
    done
fi

# ========== Resumo Final ==========
echo -e "\n📊 Resultado Final da Verificação:"
if [[ $EXIT_STATUS -eq 0 ]]; then
    log_success "TODOS OS TESTES BÁSICOS DE REDE PASSARAM!"
    log_info "Recomendação: O ambiente de rede parece estar pronto para o Proxmox VE."
else
    log_error "PROBLEMAS DETECTADOS NA CONFIGURAÇÃO DE REDE! Por favor, revise os itens marcados com ❌."
    log_info "Recomendação: Resolva os problemas antes de prosseguir com a instalação do Proxmox VE."
fi
echo "----------------------------------------"

# ========== Limpeza de Logs Antigos ==========
# Realiza a limpeza de logs no final da execução, mantendo o diretório organizado.
log_info "Realizando limpeza de logs antigos na pasta '$LOG_DIR' (mantendo os últimos $LOG_RETENTION_DAYS dias)..."
find "$LOG_DIR" -name "verifica-rede-*.log" -mtime +"$LOG_RETENTION_DAYS" -delete # Usa -delete para remover arquivos mais antigos.
log_success "Limpeza de logs concluída."

exit "$EXIT_STATUS" # O script sai com 0 para sucesso ou 1 para falha, útil para automação.