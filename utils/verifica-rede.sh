#!/usr/bin/env bash
# diagnostico-proxmox-ambiente.sh - Script de diagnóstico abrangente para ambiente Proxmox VE
# Autor: VIPs-com
# Versão: 1.v4.3
# Data: 2025-06-05
#
# Uso:
#   Execute diretamente: ./diagnostico-proxmox-ambiente.sh
#   Modo silencioso (apenas status de saída): ./diagnostico-proxmox-ambiente.sh -s
#   Verificar versão: ./diagnostico-proxmox-ambiente.sh --version
#   Com IPs/Portas personalizados via variáveis de ambiente (use vírgula):
#     CLUSTER_PEER_IPS="172.20.220.20,177.20.220.21" ESSENTIAL_PORTS="22,8006" ./diagnostico-proxmox-ambiente.sh

# ========== Configurações Padrão ==========
TIMEOUT=2 # Timeout para comandos de rede em segundos
# IPs de peers do cluster Proxmox (adicione todos os nós do cluster, incluindo o próprio)
CLUSTER_PEER_IPS=("172.20.220.20" "172.20.220.21")
# IPs essenciais para conectividade geral (ex: gateway, DNS públicos como 8.8.8.8, NTP servers)
GENERAL_CONNECTIVITY_IPS=("172.20.220.1" "8.8.8.8" "pool.ntp.org")
# Portas TCP/UDP essenciais do Proxmox e SSH.
# 22: SSH (TCP)
# 8006: Proxmox WebUI (TCP)
# 5404-5405: Corosync (UDP para cluster, ambas são importantes)
ESSENTIAL_PORTS=("22" "8006" "5404" "5405")
# Interface de rede principal do Proxmox (geralmente vmbr0)
PROXMOX_BRIDGE_INTERFACE="vmbr0"
# Host para teste de resolução DNS (direta e reversa)
DNS_TEST_HOST="google.com"
# Serviços essenciais do Proxmox VE
PROXMOX_SERVICES=("corosync" "pve-cluster" "pvedaemon" "pvestatd" "pveproxy" "systemd-timesyncd")
# Servidores NTP para verificação (adicione os seus, se tiver)
NTP_SERVERS=("0.pool.ntp.org" "1.pool.ntp.org" "2.pool.ntp.org")

# Sobrescreve IPs e portas padrão se as variáveis de ambiente estiverem definidas.
[[ -n "$CLUSTER_IPS" ]] && IFS=',' read -r -a CLUSTER_PEER_IPS <<< "$CLUSTER_IPS"
[[ -n "$PORTS" ]] && IFS=',' read -r -a ESSENTIAL_PORTS <<< "$PORTS"

# ========== Configuração de Logs ==========
LOG_DIR="/var/log/diagnostico-proxmox" # Nova pasta de logs para este script.
mkdir -p "$LOG_DIR" # Cria a pasta se não existir.
LOG_FILE="$LOG_DIR/diagnostico-$(date +%Y%m%d-%H%M%S).log" # Log com data e hora para cada execução.
LOG_RETENTION_DAYS=15 # Dias para manter os logs antes da limpeza automática.

# ========== Estado do Script ==========
EXIT_STATUS=0 # Variável para controlar o status de saída final (0 = sucesso, 1 = falha).
declare -a ERRO_DETALHES # Array para armazenar mensagens de erro detalhadas para o resumo.
declare -a AVISO_DETALHES # Array para armazenar mensagens de aviso detalhadas para o resumo.

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
    echo "diagnostico-proxmox-ambiente.sh v1.v4.3"
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
log_error()   {
    echo -e "❌ ${VERMELHO}$@${SEM_COR}";
    ERRO_DETALHES+=("$@");
    EXIT_STATUS=1;
}
log_aviso()   {
    echo -e "⚠️  ${AMARELO}$@${SEM_COR}";
    AVISO_DETALHES+=("$@");
}


# ========== Funções de Teste e Validação ==========
# is_valid_ipv4: Valida o formato de um endereço IPv4.
is_valid_ipv4() {
    local ip=$1
    [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
    local IFS=.
    local i
    for i in $ip; do
        [[ "$i" -lt 0 || "$i" -gt 255 ]] && return 1
    done
    return 0
}

# test_port_connectivity: Tenta conectar a uma porta TCP/UDP remota.
# Uso: test_port_connectivity <IP> <PORTA> [tcp|udp]
test_port_connectivity() {
    local ip=$1
    local port=$2
    local proto=${3:-tcp} # Padrão é TCP se não especificado.
    local result=1

    if [[ "$proto" == "tcp" ]]; then
        timeout "$TIMEOUT" bash -c "cat < /dev/null > /dev/tcp/$ip/$port" 2>/dev/null
        result=$?
    elif [[ "$proto" == "udp" ]]; then
        # Para UDP, é mais difícil testar a conexão sem um serviço na outra ponta respondendo.
        # nc -uz é uma tentativa, mas pode ser enganoso (sem resposta = OK, mas pode ser bloqueado).
        # Para Corosync (5404/5405), o teste de ping de cluster é mais relevante,
        # e o status do pvecm status é a confirmação final.
        timeout "$TIMEOUT" nc -uz "$ip" "$port" 2>/dev/null
        result=$?
    fi
    return $result
}

# test_ping_latency: Realiza testes de ping e mede a latência.
test_ping_latency() {
    local ip=$1
    local avg_ping
    avg_ping=$(ping -c 4 -W "$TIMEOUT" "$ip" | awk -F'/' '/rtt/ {print $5}')
    if [[ -z "$avg_ping" ]]; then
        return 1 # Falha
    else
        echo "$avg_ping" # Retorna a latência
        return 0 # Sucesso
    fi
}

# check_mtu: Verifica o MTU da interface de rede principal do Proxmox.
check_mtu() {
    local optimal_mtu=1500 # MTU ideal para a maioria das redes Gigabit Ethernet.
    local current_mtu=$(ip link show "$PROXMOX_BRIDGE_INTERFACE" 2>/dev/null | awk '/mtu/ {print $5; exit}')
    if [[ -z "$current_mtu" ]]; then
        log_aviso "Não foi possível determinar o MTU da interface '$PROXMOX_BRIDGE_INTERFACE'. Verifique o nome da interface."
        return 1
    elif [[ "$current_mtu" -lt "$optimal_mtu" ]]; then
        log_aviso "MTU da interface '$PROXMOX_BRIDGE_INTERFACE' é ${current_mtu} (Recomendado: ${optimal_mtu}). Pode haver fragmentação de pacotes."
        return 1
    else
        log_success "MTU da interface '$PROXMOX_BRIDGE_INTERFACE' é ${current_mtu} (OK)."
        return 0
    fi
}

# check_service_status: Verifica se um serviço systemd está ativo.
check_service_status() {
    local service_name=$1
    systemctl is-active --quiet "$service_name"
    if [[ $? -eq 0 ]]; then
        log_success "Serviço '$service_name' está ativo."
        return 0
    else
        log_error "Serviço '$service_name' NÃO está ativo. Verifique com 'systemctl status $service_name'."
        return 1
    fi
}

# check_hostname_resolution: Verifica se o hostname resolve para o IP correto (local e outros nós).
check_hostname_resolution() {
    local host=$1
    local expected_ip=$2
    local resolved_ip=$(dig +short "$host" 2>/dev/null)

    if [[ -z "$resolved_ip" ]]; then
        log_error "Resolução de $host: Falha. O nome não está sendo resolvido."
        return 1
    elif [[ "$resolved_ip" != "$expected_ip" ]]; then
        log_error "Resolução de $host: IP incorreto. Resolveu para $resolved_ip, esperado $expected_ip."
        return 1
    else
        log_success "Resolução de $host: OK ($resolved_ip)."
        return 0
    fi
}

# check_reverse_dns: Verifica a resolução DNS reversa.
check_reverse_dns() {
    local ip=$1
    local resolved_hostname=$(dig +short -x "$ip" 2>/dev/null | sed 's/\.$//')

    if [[ -z "$resolved_hostname" ]]; then
        log_error "Resolução DNS Reversa para $ip: Falha. Sem registro PTR."
        return 1
    else
        log_success "Resolução DNS Reversa para $ip: OK ($resolved_hostname)."
        return 0
    fi
}

# check_ntp_sync: Verifica a sincronização de tempo.
check_ntp_sync() {
    local ntp_status
    if command -v timedatectl >/dev/null 2>&1; then
        # Verifica se a propriedade NTPSynchronized é 'yes'
        if timedatectl show | grep -q 'NTPSynchronized=yes'; then
            log_success "Sincronização de tempo (NTP) está ativa."
            return 0
        else
            log_error "Sincronização de tempo (NTP) NÃO está ativa. Verifique 'timedatectl status'."
            return 1
        fi
    elif command -v ntpq >/dev/null 2>&1; then
        if ntpq -p >/dev/null 2>&1; then
            log_success "Serviço NTP parece estar funcionando (via ntpq)."
            return 0
        else
            log_error "Serviço NTP não parece estar funcionando (via ntpq). Verifique 'systemctl status ntp'."
            return 1
        fi
    else
        log_aviso "Ferramentas de verificação NTP (timedatectl ou ntpq) não encontradas. Impossível verificar sincronização de tempo."
        return 1
    fi
}

# check_corosync_status: Verifica o status do cluster Corosync.
check_corosync_status() {
    if ! command -v pvecm >/dev/null 2>&1; then
        log_aviso "Comando 'pvecm' não encontrado. Não é possível verificar o status do cluster Corosync. (Isso pode ser normal se o Proxmox ainda não estiver totalmente instalado)."
        return 1
    fi

    local cluster_nodes=$(pvecm status 2>/dev/null | grep 'Total votes:' | awk '{print $NF}')
    if [[ -z "$cluster_nodes" ]]; then
        log_error "Não foi possível obter o status do cluster Corosync via 'pvecm status'. O cluster pode não estar formado ou o serviço está inativo."
        return 1
    elif [[ "$cluster_nodes" -lt 1 ]]; then
        log_error "Corosync: Total de votos no cluster é 0. O cluster pode não estar totalmente online ou não está sincronizado."
        return 1
    else
        log_success "Corosync: Cluster parece estar formado com $cluster_nodes voto(s)."
        return 0
    fi
}

# check_disk_health: Verifica a saúde dos discos via SMART e ZFS
check_disk_health() {
    log_cabecalho "8/12 - Verificação de Armazenamento e Discos"
    if ! command -v smartctl >/dev/null 2>&1; then
        log_aviso "Comando 'smartctl' não encontrado. Instale 'smartmontools' para verificar a saúde dos discos."
    else
        log_info "Verificando saúde dos discos via SMART:"
        local disks=$(lsblk -dn -o NAME,TYPE | grep disk | awk '{print $1}')
        if [[ -z "$disks" ]]; then
            log_aviso "Nenhum disco físico encontrado para verificação SMART."
        else
            for disk in $disks; do
                log_info "  Verificando /dev/$disk..."
                if smartctl -H /dev/"$disk" | grep -q "SMART overall-health self-assessment test result: PASSED"; then
                    log_success "    /dev/$disk: Teste SMART passou (OK)."
                else
                    log_error "    /dev/$disk: Teste SMART FALHOU ou com avisos! Verifique 'smartctl -a /dev/$disk' para detalhes."
                fi
            done
        fi
    fi

    if command -v zpool >/dev/null 2>&1; then
        log_info "Verificando saúde dos pools ZFS:"
        local zpools=$(zpool list -H -o name)
        if [[ -z "$zpools" ]]; then
            log_aviso "Nenhum pool ZFS encontrado."
        else
            for pool in $zpools; do
                log_info "  Verificando pool '$pool'..."
                if zpool status "$pool" | grep -q "state: ONLINE"; then
                    if zpool status "$pool" | grep -q "status: The pool is currently healthy"; then
                        log_success "    Pool '$pool' está ONLINE e saudável."
                    else
                        log_aviso "    Pool '$pool' está ONLINE, mas com avisos/erros. Verifique 'zpool status $pool'."
                    fi
                else
                    log_error "    Pool '$pool' NÃO está ONLINE! Verifique 'zpool status $pool' URGENTE!"
                fi
            done
        fi
    else
        log_aviso "Comando 'zpool' não encontrado. Ignorando verificação de ZFS."
    fi

    log_info "Verificando espaço em disco nas partições críticas:"
    local critical_partitions=("/" "/var" "/boot" "/home" "/tmp")
    for part in "${critical_partitions[@]}"; do
        if df -h "$part" >/dev/null 2>&1; then
            local usage=$(df -h "$part" | awk 'NR==2 {print $5}' | sed 's/%//')
            if [[ "$usage" -ge 90 ]]; then
                log_error "  Uso de disco em '$part': ${usage}% (CRÍTICO! Espaço quase esgotado)."
            elif [[ "$usage" -ge 80 ]]; then
                log_aviso "  Uso de disco em '$part': ${usage}% (ALTO! Considere liberar espaço)."
            else
                log_success "  Uso de disco em '$part': ${usage}% (OK)."
            fi
        else
            log_aviso "  Partição '$part' não encontrada ou não montada. Ignorando verificação de espaço."
        fi
    done
}

# check_system_logs: Analisa logs do sistema para erros e avisos
check_system_logs() {
    log_cabecalho "9/12 - Análise de Logs do Sistema"
    if ! command -v journalctl >/dev/null 2>&1; then
        log_aviso "Comando 'journalctl' não encontrado. Não é possível analisar logs do sistema."
    else
        log_info "Verificando logs do sistema (últimas 50 linhas com erro/aviso):"
        local journal_output=$(journalctl -p err -p warning -b -n 50 --no-pager 2>/dev/null)
        if [[ -n "$journal_output" ]]; then
            log_error "  Erros/Avisos recentes no journalctl detectados. Verifique os logs para detalhes:"
            echo "$journal_output" | sed 's/^/    /' # Indenta a saída
        else
            log_success "  Nenhum erro ou aviso crítico recente no journalctl."
        fi
    fi

    if ! command -v dmesg >/dev/null 2>&1; then
        log_aviso "Comando 'dmesg' não encontrado. Não é possível analisar logs do kernel."
    else
        log_info "Verificando logs do kernel (últimas 50 linhas com erro/aviso):"
        local dmesg_output=$(dmesg -T | tail -n 50 | grep -iE "error|fail|warn|crit" 2>/dev/null)
        if [[ -n "$dmesg_output" ]]; then
            log_error "  Erros/Avisos recentes no kernel (dmesg) detectados. Verifique os logs para detalhes:"
            echo "$dmesg_output" | sed 's/^/    /' # Indenta a saída
        else
            log_success "  Nenhum erro ou aviso crítico recente no kernel (dmesg)."
        fi
    fi
}

# check_resource_usage: Verifica a utilização básica de CPU, Memória e Swap
check_resource_usage() {
    log_cabecalho "10/12 - Verificação de Utilização de Recursos"
    log_info "Verificando carga do sistema (Load Average):"
    local load_avg=$(uptime | awk -F'load average: ' '{print $2}')
    log_info "  Load Average (1min, 5min, 15min): $load_avg"
    local load_1min=$(echo "$load_avg" | cut -d',' -f1 | sed 's/ //g')
    local num_cpus=$(nproc)
    if (( $(echo "$load_1min > $num_cpus * 0.8" | bc -l) )); then # Se carga > 80% dos CPUs
        log_aviso "  Carga do sistema (1min) está alta (${load_1min}). Número de CPUs: ${num_cpus}. Pode indicar sobrecarga."
    else
        log_success "  Carga do sistema (Load Average) OK."
    fi

    log_info "Verificando uso de Memória e Swap:"
    local mem_total=$(free -h | awk '/^Mem:/ {print $2}')
    local mem_used=$(free -h | awk '/^Mem:/ {print $3}')
    local mem_free=$(free -h | awk '/^Mem:/ {print $4}')
    local swap_total=$(free -h | awk '/^Swap:/ {print $2}')
    local swap_used=$(free -h | awk '/^Swap:/ {print $3}')
    local swap_percent=$(free | awk '/^Swap:/ {printf "%.0f\n", $3*100/$2 }') # Porcentagem de swap usada

    log_info "  Memória Total: $mem_total, Usada: $mem_used, Livre: $mem_free"
    log_info "  Swap Total: $swap_total, Usada: $swap_used"

    if [[ "$swap_used" != "0B" && "$swap_percent" -ge 20 ]]; then # Se swap usado e mais de 20%
        log_aviso "  Uso de Swap está em ${swap_percent}%. Considere adicionar mais RAM ou otimizar o uso de memória."
    else
        log_success "  Uso de Memória e Swap OK."
    fi
}

# check_proxmox_consistency: Verifica a versão do Proxmox e atualizações pendentes
check_proxmox_consistency() {
    log_cabecalho "11/12 - Verificação de Consistência e Atualizações do Proxmox"
    log_info "Verificando versão do Proxmox VE:"
    local pve_version=$(pveversion | grep "pve-manager" | awk '{print $2}')
    if [[ -n "$pve_version" ]]; then
        log_success "  Versão do Proxmox VE: $pve_version."
    else
        log_error "  Não foi possível determinar a versão do Proxmox VE."
    fi

    log_info "Verificando pacotes pendentes de atualização:"
    local upgradable_packages=$(apt list --upgradable 2>/dev/null | grep -v "Listing..." | wc -l)
    if [[ "$upgradable_packages" -gt 0 ]]; then
        log_aviso "  Há $upgradable_packages pacotes pendentes de atualização. Execute 'apt update && apt dist-upgrade -y'."
        apt list --upgradable 2>/dev/null | grep -v "Listing..." | sed 's/^/    - /' # Lista os pacotes
    else
        log_success "  Nenhum pacote Proxmox ou do sistema pendente de atualização."
    fi
}

# check_advanced_network_config: Verifica configurações de rede avançadas como bonds e VLANs
check_advanced_network_config() {
    log_cabecalho "12/12 - Verificação de Configuração de Rede Avançada"
    log_info "Analisando /etc/network/interfaces:"
    if [ -f "/etc/network/interfaces" ]; then
        log_info "  Conteúdo de /etc/network/interfaces:"
        cat /etc/network/interfaces | sed 's/^/    /' # Indenta a saída
    else
        log_error "  Arquivo /etc/network/interfaces não encontrado. Configuração de rede pode estar ausente ou incorreta."
        return 1
    fi

    log_info "Verificando status de Bonds (agregação de links):"
    local bonds=$(grep -lR "bond-slaves" /etc/network/interfaces 2>/dev/null | xargs grep -oP 'iface \Kbond\d+' | sort -u)
    if [[ -n "$bonds" ]]; then
        for bond in $bonds; do
            log_info "  Verificando bond '$bond'..."
            if [ -f "/proc/net/bonding/$bond" ]; then
                local bond_status=$(cat /proc/net/bonding/"$bond" | grep "MII Status" | awk '{print $NF}')
                local num_slaves=$(cat /proc/net/bonding/"$bond" | grep "Number of Slaves" | awk '{print $NF}')
                local active_slaves=$(cat /proc/net/bonding/"$bond" | grep "Slave Interface" | grep "Up" | wc -l)
                log_info "    Status: $bond_status, Slaves: $num_slaves, Ativos: $active_slaves"
                if [[ "$bond_status" == "up" && "$active_slaves" -eq "$num_slaves" ]]; then
                    log_success "    Bond '$bond' está ativo e todos os links estão UP."
                else
                    log_error "    Bond '$bond' com problemas! Status: $bond_status, Links Ativos: $active_slaves/$num_slaves. Verifique 'cat /proc/net/bonding/$bond'."
                fi
            else
                log_error "  Bond '$bond' configurado, mas /proc/net/bonding/$bond não encontrado. Pode não estar ativo."
            fi
        done
    else
        log_info "  Nenhum bond (agregação de links) configurado."
    fi

    log_info "Verificando presença de VLANs:"
    if grep -q "vlan-raw-device" /etc/network/interfaces; then
        log_aviso "  VLANs detectadas. Certifique-se de que as configurações de VLAN estão corretas e que os switches estão configurados adequadamente."
        grep "vlan-raw-device" /etc/network/interfaces | sed 's/^/    - /' # Lista as VLANs
    else
        log_info "  Nenhuma VLAN configurada diretamente em /etc/network/interfaces."
    fi
}


# ========== Checagem de Dependências Essenciais ==========
log_cabecalho "Verificando Dependências Essenciais do Sistema"
REQUIRED_COMMANDS=("ping" "dig" "timeout" "ip" "ss" "systemctl" "awk" "grep" "sed" "lsblk" "df" "free" "uptime" "nproc" "wc")
# Adicionar ntpq ou timedatectl dependendo do que estiver disponível.
if command -v timedatectl >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("timedatectl")
elif command -v ntpq >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("ntpq")
fi
if command -v pvecm >/dev/null 2>&1; then # pvecm só existirá se proxmox já estiver instalado
    REQUIRED_COMMANDS+=("pvecm")
fi
if command -v smartctl >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("smartctl")
fi
if command -v zpool >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("zpool" "zfs")
fi
if command -v journalctl >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("journalctl")
fi
if command -v dmesg >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("dmesg")
fi


for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Dependência ausente: '$cmd' não encontrado. Por favor, instale-a."
        case "$cmd" in
            "ping") log_info "  Sugestão: apt install -y iputils-ping" ;;
            "dig") log_info "  Sugestão: apt install -y dnsutils" ;;
            "timeout") log_info "  Sugestão: apt install -y coreutils" ;;
            "ip") log_info "  Sugestão: apt install -y iproute2" ;;
            "ss") log_info "  Sugestão: apt install -y iproute2" ;;
            "systemctl") log_info "  Sugestão: Faz parte do systemd, se ausente, o sistema está comprometido." ;;
            "timedatectl") log_info "  Sugestão: Faz parte do systemd, verifique a instalação." ;;
            "ntpq") log_info "  Sugestão: apt install -y ntp" ;;
            "pvecm") log_info "  Sugestão: Faça a instalação básica do Proxmox VE." ;;
            "smartctl") log_info "  Sugestão: apt install -y smartmontools" ;;
            "zpool"|"zfs") log_info "  Sugestão: apt install -y zfsutils-linux" ;;
            "journalctl") log_info "  Sugestão: Faz parte do systemd, verifique a instalação." ;;
            "dmesg") log_info "  Sugestão: Faz parte do kmod, verifique a instalação." ;;
            "lsblk") log_info "  Sugestão: apt install -y util-linux" ;;
            "df"|"free") log_info "  Sugestão: apt install -y coreutils" ;;
            "uptime") log_info "  Sugestão: apt install -y procps" ;;
            "nproc") log_info "  Sugestão: apt install -y coreutils" ;;
            "wc") log_info "  Sugestão: apt install -y coreutils" ;;
            "cat") log_info "  Sugestão: apt install -y coreutils" ;;
            "grep") log_info "  Sugestão: apt install -y grep" ;;
            "sed") log_info "  Sugestão: apt install -y sed" ;;
            "awk") log_info "  Sugestão: apt install -y gawk" ;;
        esac
        # Não sai imediatamente aqui, apenas registra o erro, para que o script possa continuar
        # e reportar todas as dependências ausentes antes de um possível exit final.
        EXIT_STATUS=1
    else
        log_success "'$cmd' encontrado."
    fi
done

# Se houver dependências ausentes, aborta aqui.
if [[ $EXIT_STATUS -ne 0 ]]; then
    log_error "Algumas dependências essenciais estão ausentes. Por favor, instale-as e execute o script novamente."
    exit 1
fi

# ========== Validação Inicial das Configurações do Script ==========
log_cabecalho "Validando Configurações do Script"
# Valida IPs de peers
if [[ ${#CLUSTER_PEER_IPS[@]} -eq 0 ]]; then
    log_aviso "Nenhum IP de peer configurado em CLUSTER_PEER_IPS. Testes de comunicação entre nós serão limitados."
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

# Valida IPs de conectividade geral
if [[ ${#GENERAL_CONNECTIVITY_IPS[@]} -eq 0 ]]; then
    log_aviso "Nenhum IP de conectividade geral configurado. Testes de ping básicos serão pulados."
else
    for ip in "${GENERAL_CONNECTIVITY_IPS[@]}"; do
        if ! is_valid_ipv4 "$ip" && ! [[ "$ip" =~ ^[a-zA-Z0-9\.-]+$ ]]; then # Permite IPs ou hostnames
            log_error "Entrada inválida em GENERAL_CONNECTIVITY_IPS: '$ip'. Use um IP válido ou hostname."
            EXIT_STATUS=1
        else
            log_success "Entrada de conectividade geral: $ip (válida)."
        fi
    done
fi

# Valida Portas Essenciais
if [[ ${#ESSENTIAL_PORTS[@]} -eq 0 ]]; then
    log_aviso "Nenhuma porta essencial configurada em ESSENTIAL_PORTS. Testes de portas serão pulados."
else
    for port in "${ESSENTIAL_PORTS[@]}"; do
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
            log_error "Porta inválida configurada em ESSENTIAL_PORTS: '$port'. Por favor, corrija."
            EXIT_STATUS=1
        else
            log_success "Porta essencial configurada: $port (válida)."
        fi
    done
fi

# Aborta se as configurações iniciais estiverem inválidas.
[[ $EXIT_STATUS -ne 0 ]] && { log_error "Por favor, corrija as configurações no script e execute novamente."; exit 1; }

# ========== Execução dos Testes de Ambiente ==========
clear # Limpa a tela para uma saída limpa no terminal.
log_info "🔍 Iniciando Diagnóstico de Ambiente para Proxmox VE - $(date)."
HOSTNAME_LOCAL=$(hostname)
IP_LOCAL=$(hostname -I | awk '{print $1}')
log_info "Hostname local deste nó: $HOSTNAME_LOCAL"
log_info "IP local deste nó: $IP_LOCAL"
echo "----------------------------------------"

# 1. Verificação de Conectividade Geral (Internet/Gateway/NTP)
log_cabecalho "1/12 - Verificando Conectividade Geral (Internet/Gateway/NTP)"
if [[ ${#GENERAL_CONNECTIVITY_IPS[@]} -eq 0 ]]; then
    log_aviso "Testes de conectividade geral pulados (Nenhum IP/Hostname configurado em GENERAL_CONNECTIVITY_IPS)."
else
    for dest in "${GENERAL_CONNECTIVITY_IPS[@]}"; do
        ping_result=$(test_ping_latency "$dest")
        if [[ $? -eq 0 ]]; then
            log_success "  $dest → Latência média: ${ping_result}ms."
        else
            log_error "  $dest → Falha no ping ou timeout. Verifique conectividade externa/gateway."
        fi
    done
fi

# 2. Teste de Resolução DNS (Direta e Reversa)
log_cabecalho "2/12 - Testando Resolução DNS"
# Teste de resolução DNS direta
log_info "  Testando resolução DNS para $DNS_TEST_HOST..."
resolved_ip_dns_test=$(dig +short "$DNS_TEST_HOST" 2>/dev/null)
if [[ -z "$resolved_ip_dns_test" ]]; then
    log_error "  Resolução DNS para '$DNS_TEST_HOST': Falha. Verifique seu servidor DNS em /etc/resolv.conf."
else
    log_success "  Resolução DNS para '$DNS_TEST_HOST': OK ($resolved_ip_dns_test)."
fi

# Teste de resolução DNS reversa para IPs de cluster (apenas se CLUSTER_PEER_IPS estiver definido)
log_info "  Verificando Resolução DNS Reversa para IPs de Cluster:"
if [[ ${#CLUSTER_PEER_IPS[@]} -eq 0 ]]; then
    log_aviso "  Teste de DNS reverso para IPs de cluster pulado (Nenhum IP de peer configurado)."
else
    for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
        check_reverse_dns "$ip_peer"
    done
fi
log_info "  Verificando resolução de hostnames de cluster para IPs:"
for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
    # Tenta resolver o hostname do IP do peer
    peer_hostname=$(dig +short -x "$ip_peer" 2>/dev/null | sed 's/\.$//')
    if [[ -n "$peer_hostname" ]]; then
        check_hostname_resolution "$peer_hostname" "$ip_peer"
    else
        log_aviso "  Não foi possível obter hostname reverso para $ip_peer para teste de resolução. Verifique DNS reverso."
    fi
done


# 3. Verificação de Interface de Rede e MTU
log_cabecalho "3/12 - Verificação de Interface de Rede e MTU"
ip addr show "$PROXMOX_BRIDGE_INTERFACE" &> /dev/null
if [[ $? -eq 0 ]]; then
    log_success "Interface '$PROXMOX_BRIDGE_INTERFACE' existe."
    IP_ATRIBUIDO=$(ip -4 addr show "$PROXMOX_BRIDGE_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [[ -n "$IP_ATRIBUIDO" ]]; then
        log_info "IP atribuído à '$PROXMOX_BRIDGE_INTERFACE': $IP_ATRIBUIDO."
        if [[ "$IP_ATRIBUIDO" != "$IP_LOCAL" ]]; then
             log_aviso "O IP principal da interface '$PROXMOX_BRIDGE_INTERFACE' ($IP_ATRIBUIDO) não coincide com o IP detectado localmente ($IP_LOCAL). Pode indicar um problema."
        fi
    else
        log_error "Interface '$PROXMOX_BRIDGE_INTERFACE' NÃO tem IP IPv4 atribuído. Essencial para o Proxmox."
    fi
    check_mtu
else
    log_error "Interface '$PROXMOX_BRIDGE_INTERFACE' NÃO encontrada. É crítica para a rede do Proxmox."
fi

# 4. Testes de Latência e Portas entre Nós do Cluster
log_cabecalho "4/12 - Testes de Latência e Portas (Comunicação de Cluster)"
if [[ ${#CLUSTER_PEER_IPS[@]} -le 1 ]]; then # Se só tem 1 ou nenhum IP configurado, não é um cluster para testar comunicação entre nós
    log_aviso "Apenas um ou nenhum IP de peer configurado em CLUSTER_PEER_IPS. Testes de comunicação entre nós serão limitados/pulados."
else
    log_info "Medição de Latência entre Nós do Cluster:"
    for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
        if [[ "$ip_peer" != "$IP_LOCAL" ]]; then # Não testa ping para si mesmo se já foi o IP local.
            ping_result=$(test_ping_latency "$ip_peer")
            if [[ $? -eq 0 ]]; then
                log_success "  $ip_peer → Latência média: ${ping_result}ms."
            else
                log_error "  $ip_peer → Falha no ping ou timeout. A comunicação com este nó está comprometida."
            fi
        fi
    done

    log_info "Verificando Portas Essenciais entre Nós do Cluster:"
    if [[ ${#ESSENTIAL_PORTS[@]} -eq 0 ]]; then
        log_aviso "Nenhuma porta essencial configurada. Testes de portas pulados."
    else
        for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
            if [[ "$ip_peer" != "$IP_LOCAL" ]]; then
                log_info "🔧 Verificando Nó $ip_peer (de $IP_LOCAL):"
                for port in "${ESSENTIAL_PORTS[@]}"; do
                    # Assumimos TCP para SSH e WebUI, UDP para Corosync
                    PROTO="tcp"
                    if [[ "$port" -ge 5404 && "$port" -le 5405 ]]; then
                        PROTO="udp"
                    fi

                    # Lógica de verificação para portas UDP do Corosync
                    if [[ "$PROTO" == "udp" && ("$port" == "5404" || "$port" == "5405") ]]; then
                        # Se o cluster está quorate, assumimos que as portas Corosync estão OK
                        if check_corosync_status >/dev/null 2>&1; then # Verifica se o cluster está quorate
                            log_success "  Porta $port ($PROTO) → Acessível (Cluster Corosync OK)."
                        else
                            # Se o cluster não está quorate, o erro é real
                            log_error "  Porta $port ($PROTO) → Bloqueada/Inacessível. ESSENCIAL para comunicação de cluster. Verifique regras de firewall."
                        fi
                    else
                        # Para outras portas TCP/UDP, usa o teste de conectividade padrão
                        if test_port_connectivity "$ip_peer" "$port" "$PROTO"; then
                            log_success "  Porta $port ($PROTO) → Acessível."
                        else
                            log_error "  Porta $port ($PROTO) → Bloqueada/Inacessível. ESSENCIAL para comunicação de cluster. Verifique regras de firewall."
                        fi
                    fi
                done
            fi
        done
    fi
fi

# 5. Verificação de Sincronização de Tempo (NTP)
log_cabecalho "5/12 - Verificação de Sincronização de Tempo (NTP)"
check_ntp_sync

# 6. Verificação dos Serviços Essenciais do Proxmox VE
log_cabecalho "6/12 - Verificando Serviços Essenciais do Proxmox VE"
for servico in "${PROXMOX_SERVICES[@]}"; do
    check_service_status "$servico"
done

# 7. Verificação do Status do Cluster Corosync (se pvecm estiver disponível)
log_cabecalho "7/12 - Verificação do Status do Cluster Corosync"
check_corosync_status # Esta função lida com a ausência de pvecm.

# 8. Verificação de Armazenamento e Discos
check_disk_health

# 9. Análise de Logs do Sistema
check_system_logs

# 10. Verificação de Utilização de Recursos
check_resource_usage

# 11. Verificação de Consistência e Atualizações do Proxmox
check_proxmox_consistency

# 12. Verificação de Configuração de Rede Avançada
check_advanced_network_config


# ========== Checagem de Dependências Essenciais ==========
log_cabecalho "Verificando Dependências Essenciais do Sistema"
REQUIRED_COMMANDS=("ping" "dig" "timeout" "ip" "ss" "systemctl" "awk" "grep" "sed" "lsblk" "df" "free" "uptime" "nproc" "wc")
# Adicionar ntpq ou timedatectl dependendo do que estiver disponível.
if command -v timedatectl >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("timedatectl")
elif command -v ntpq >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("ntpq")
fi
if command -v pvecm >/dev/null 2>&1; then # pvecm só existirá se proxmox já estiver instalado
    REQUIRED_COMMANDS+=("pvecm")
fi
if command -v smartctl >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("smartctl")
fi
if command -v zpool >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("zpool" "zfs")
fi
if command -v journalctl >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("journalctl")
fi
if command -v dmesg >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("dmesg")
fi


for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Dependência ausente: '$cmd' não encontrado. Por favor, instale-a."
        case "$cmd" in
            "ping") log_info "  Sugestão: apt install -y iputils-ping" ;;
            "dig") log_info "  Sugestão: apt install -y dnsutils" ;;
            "timeout") log_info "  Sugestão: apt install -y coreutils" ;;
            "ip") log_info "  Sugestão: apt install -y iproute2" ;;
            "ss") log_info "  Sugestão: apt install -y iproute2" ;;
            "systemctl") log_info "  Sugestão: Faz parte do systemd, se ausente, o sistema está comprometido." ;;
            "timedatectl") log_info "  Sugestão: Faz parte do systemd, verifique a instalação." ;;
            "ntpq") log_info "  Sugestão: apt install -y ntp" ;;
            "pvecm") log_info "  Sugestão: Faça a instalação básica do Proxmox VE." ;;
            "smartctl") log_info "  Sugestão: apt install -y smartmontools" ;;
            "zpool"|"zfs") log_info "  Sugestão: apt install -y zfsutils-linux" ;;
            "journalctl") log_info "  Sugestão: Faz parte do systemd, verifique a instalação." ;;
            "dmesg") log_info "  Sugestão: Faz parte do kmod, verifique a instalação." ;;
            "lsblk") log_info "  Sugestão: apt install -y util-linux" ;;
            "df"|"free") log_info "  Sugestão: apt install -y coreutils" ;;
            "uptime") log_info "  Sugestão: apt install -y procps" ;;
            "nproc") log_info "  Sugestão: apt install -y coreutils" ;;
            "wc") log_info "  Sugestão: apt install -y coreutils" ;;
            "cat") log_info "  Sugestão: apt install -y coreutils" ;;
            "grep") log_info "  Sugestão: apt install -y grep" ;;
            "sed") log_info "  Sugestão: apt install -y sed" ;;
            "awk") log_info "  Sugestão: apt install -y gawk" ;;
        esac
        # Não sai imediatamente aqui, apenas registra o erro, para que o script possa continuar
        # e reportar todas as dependências ausentes antes de um possível exit final.
        EXIT_STATUS=1
    else
        log_success "'$cmd' encontrado."
    fi
done

# Se houver dependências ausentes, aborta aqui.
if [[ $EXIT_STATUS -ne 0 ]]; then
    log_error "Algumas dependências essenciais estão ausentes. Por favor, instale-as e execute o script novamente."
    exit 1
fi

# ========== Validação Inicial das Configurações do Script ==========
log_cabecalho "Validando Configurações do Script"
# Valida IPs de peers
if [[ ${#CLUSTER_PEER_IPS[@]} -eq 0 ]]; then
    log_aviso "Nenhum IP de peer configurado em CLUSTER_PEER_IPS. Testes de comunicação entre nós serão limitados."
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

# Valida IPs de conectividade geral
if [[ ${#GENERAL_CONNECTIVITY_IPS[@]} -eq 0 ]]; then
    log_aviso "Nenhum IP de conectividade geral configurado. Testes de ping básicos serão pulados."
else
    for ip in "${GENERAL_CONNECTIVITY_IPS[@]}"; do
        if ! is_valid_ipv4 "$ip" && ! [[ "$ip" =~ ^[a-zA-Z0-9\.-]+$ ]]; then # Permite IPs ou hostnames
            log_error "Entrada inválida em GENERAL_CONNECTIVITY_IPS: '$ip'. Use um IP válido ou hostname."
            EXIT_STATUS=1
        else
            log_success "Entrada de conectividade geral: $ip (válida)."
        fi
    done
fi

# Valida Portas Essenciais
if [[ ${#ESSENTIAL_PORTS[@]} -eq 0 ]]; then
    log_aviso "Nenhuma porta essencial configurada em ESSENTIAL_PORTS. Testes de portas serão pulados."
else
    for port in "${ESSENTIAL_PORTS[@]}"; do
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
            log_error "Porta inválida configurada em ESSENTIAL_PORTS: '$port'. Por favor, corrija."
            EXIT_STATUS=1
        else
            log_success "Porta essencial configurada: $port (válida)."
        fi
    done
fi

# Aborta se as configurações iniciais estiverem inválidas.
[[ $EXIT_STATUS -ne 0 ]] && { log_error "Por favor, corrija as configurações no script e execute novamente."; exit 1; }

# ========== Execução dos Testes de Ambiente ==========
clear # Limpa a tela para uma saída limpa no terminal.
log_info "🔍 Iniciando Diagnóstico de Ambiente para Proxmox VE - $(date)."
HOSTNAME_LOCAL=$(hostname)
IP_LOCAL=$(hostname -I | awk '{print $1}')
log_info "Hostname local deste nó: $HOSTNAME_LOCAL"
log_info "IP local deste nó: $IP_LOCAL"
echo "----------------------------------------"

# 1. Verificação de Conectividade Geral (Internet/Gateway/NTP)
log_cabecalho "1/12 - Verificando Conectividade Geral (Internet/Gateway/NTP)"
if [[ ${#GENERAL_CONNECTIVITY_IPS[@]} -eq 0 ]]; then
    log_aviso "Testes de conectividade geral pulados (Nenhum IP/Hostname configurado em GENERAL_CONNECTIVITY_IPS)."
else
    for dest in "${GENERAL_CONNECTIVITY_IPS[@]}"; do
        ping_result=$(test_ping_latency "$dest")
        if [[ $? -eq 0 ]]; then
            log_success "  $dest → Latência média: ${ping_result}ms."
        else
            log_error "  $dest → Falha no ping ou timeout. Verifique conectividade externa/gateway."
        fi
    done
fi

# 2. Teste de Resolução DNS (Direta e Reversa)
log_cabecalho "2/12 - Testando Resolução DNS"
# Teste de resolução DNS direta
log_info "  Testando resolução DNS para $DNS_TEST_HOST..."
resolved_ip_dns_test=$(dig +short "$DNS_TEST_HOST" 2>/dev/null)
if [[ -z "$resolved_ip_dns_test" ]]; then
    log_error "  Resolução DNS para '$DNS_TEST_HOST': Falha. Verifique seu servidor DNS em /etc/resolv.conf."
else
    log_success "  Resolução DNS para '$DNS_TEST_HOST': OK ($resolved_ip_dns_test)."
fi

# Teste de resolução DNS reversa para IPs de cluster (apenas se CLUSTER_PEER_IPS estiver definido)
log_info "  Verificando Resolução DNS Reversa para IPs de Cluster:"
if [[ ${#CLUSTER_PEER_IPS[@]} -eq 0 ]]; then
    log_aviso "  Teste de DNS reverso para IPs de cluster pulado (Nenhum IP de peer configurado)."
else
    for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
        check_reverse_dns "$ip_peer"
    done
fi
log_info "  Verificando resolução de hostnames de cluster para IPs:"
for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
    # Tenta resolver o hostname do IP do peer
    peer_hostname=$(dig +short -x "$ip_peer" 2>/dev/null | sed 's/\.$//')
    if [[ -n "$peer_hostname" ]]; then
        check_hostname_resolution "$peer_hostname" "$ip_peer"
    else
        log_aviso "  Não foi possível obter hostname reverso para $ip_peer para teste de resolução. Verifique DNS reverso."
    fi
done


# 3. Verificação de Interface de Rede e MTU
log_cabecalho "3/12 - Verificação de Interface de Rede e MTU"
ip addr show "$PROXMOX_BRIDGE_INTERFACE" &> /dev/null
if [[ $? -eq 0 ]]; then
    log_success "Interface '$PROXMOX_BRIDGE_INTERFACE' existe."
    IP_ATRIBUIDO=$(ip -4 addr show "$PROXMOX_BRIDGE_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [[ -n "$IP_ATRIBUIDO" ]]; then
        log_info "IP atribuído à '$PROXMOX_BRIDGE_INTERFACE': $IP_ATRIBUIDO."
        if [[ "$IP_ATRIBUIDO" != "$IP_LOCAL" ]]; then
             log_aviso "O IP principal da interface '$PROXMOX_BRIDGE_INTERFACE' ($IP_ATRIBUIDO) não coincide com o IP detectado localmente ($IP_LOCAL). Pode indicar um problema."
        fi
    else
        log_error "Interface '$PROXMOX_BRIDGE_INTERFACE' NÃO tem IP IPv4 atribuído. Essencial para o Proxmox."
    fi
    check_mtu
else
    log_error "Interface '$PROXMOX_BRIDGE_INTERFACE' NÃO encontrada. É crítica para a rede do Proxmox."
fi

# 4. Testes de Latência e Portas entre Nós do Cluster
log_cabecalho "4/12 - Testes de Latência e Portas (Comunicação de Cluster)"
if [[ ${#CLUSTER_PEER_IPS[@]} -le 1 ]]; then # Se só tem 1 ou nenhum IP configurado, não é um cluster para testar comunicação entre nós
    log_aviso "Apenas um ou nenhum IP de peer configurado em CLUSTER_PEER_IPS. Testes de comunicação entre nós serão limitados/pulados."
else
    log_info "Medição de Latência entre Nós do Cluster:"
    for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
        if [[ "$ip_peer" != "$IP_LOCAL" ]]; then # Não testa ping para si mesmo se já foi o IP local.
            ping_result=$(test_ping_latency "$ip_peer")
            if [[ $? -eq 0 ]]; then
                log_success "  $ip_peer → Latência média: ${ping_result}ms."
            else
                log_error "  $ip_peer → Falha no ping ou timeout. A comunicação com este nó está comprometida."
            fi
        fi
    done

    log_info "Verificando Portas Essenciais entre Nós do Cluster:"
    if [[ ${#ESSENTIAL_PORTS[@]} -eq 0 ]]; then
        log_aviso "Nenhuma porta essencial configurada. Testes de portas pulados."
    else
        for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
            if [[ "$ip_peer" != "$IP_LOCAL" ]]; then
                log_info "🔧 Verificando Nó $ip_peer (de $IP_LOCAL):"
                for port in "${ESSENTIAL_PORTS[@]}"; do
                    # Assumimos TCP para SSH e WebUI, UDP para Corosync
                    PROTO="tcp"
                    if [[ "$port" -ge 5404 && "$port" -le 5405 ]]; then
                        PROTO="udp"
                    fi

                    # Lógica de verificação para portas UDP do Corosync
                    if [[ "$PROTO" == "udp" && ("$port" == "5404" || "$port" == "5405") ]]; then
                        # Se o cluster está quorate, assumimos que as portas Corosync estão OK
                        if check_corosync_status >/dev/null 2>&1; then # Verifica se o cluster está quorate
                            log_success "  Porta $port ($PROTO) → Acessível (Cluster Corosync OK)."
                        else
                            # Se o cluster não está quorate, o erro é real
                            log_error "  Porta $port ($PROTO) → Bloqueada/Inacessível. ESSENCIAL para comunicação de cluster. Verifique regras de firewall."
                        fi
                    else
                        # Para outras portas TCP/UDP, usa o teste de conectividade padrão
                        if test_port_connectivity "$ip_peer" "$port" "$PROTO"; then
                            log_success "  Porta $port ($PROTO) → Acessível."
                        else
                            log_error "  Porta $port ($PROTO) → Bloqueada/Inacessível. ESSENCIAL para comunicação de cluster. Verifique regras de firewall."
                        </div>
                    fi
                done
            fi
        done
    fi
fi

# 5. Verificação de Sincronização de Tempo (NTP)
log_cabecalho "5/12 - Verificação de Sincronização de Tempo (NTP)"
check_ntp_sync

# 6. Verificação dos Serviços Essenciais do Proxmox VE
log_cabecalho "6/12 - Verificando Serviços Essenciais do Proxmox VE"
for servico in "${PROXMOX_SERVICES[@]}"; do
    check_service_status "$servico"
done

# 7. Verificação do Status do Cluster Corosync (se pvecm estiver disponível)
log_cabecalho "7/12 - Verificação do Status do Cluster Corosync"
check_corosync_status # Esta função lida com a ausência de pvecm.

# 8. Verificação de Armazenamento e Discos
check_disk_health

# 9. Análise de Logs do Sistema
check_system_logs

# 10. Verificação de Utilização de Recursos
check_resource_usage

# 11. Verificação de Consistência e Atualizações do Proxmox
check_proxmox_consistency

# 12. Verificação de Configuração de Rede Avançada
check_advanced_network_config


# ========== Checagem de Dependências Essenciais ==========
log_cabecalho "Verificando Dependências Essenciais do Sistema"
REQUIRED_COMMANDS=("ping" "dig" "timeout" "ip" "ss" "systemctl" "awk" "grep" "sed" "lsblk" "df" "free" "uptime" "nproc" "wc")
# Adicionar ntpq ou timedatectl dependendo do que estiver disponível.
if command -v timedatectl >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("timedatectl")
elif command -v ntpq >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("ntpq")
fi
if command -v pvecm >/dev/null 2>&1; then # pvecm só existirá se proxmox já estiver instalado
    REQUIRED_COMMANDS+=("pvecm")
fi
if command -v smartctl >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("smartctl")
fi
if command -v zpool >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("zpool" "zfs")
fi
if command -v journalctl >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("journalctl")
fi
if command -v dmesg >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("dmesg")
fi


for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Dependência ausente: '$cmd' não encontrado. Por favor, instale-a."
        case "$cmd" in
            "ping") log_info "  Sugestão: apt install -y iputils-ping" ;;
            "dig") log_info "  Sugestão: apt install -y dnsutils" ;;
            "timeout") log_info "  Sugestão: apt install -y coreutils" ;;
            "ip") log_info "  Sugestão: apt install -y iproute2" ;;
            "ss") log_info "  Sugestão: apt install -y iproute2" ;;
            "systemctl") log_info "  Sugestão: Faz parte do systemd, se ausente, o sistema está comprometido." ;;
            "timedatectl") log_info "  Sugestão: Faz parte do systemd, verifique a instalação." ;;
            "ntpq") log_info "  Sugestão: apt install -y ntp" ;;
            "pvecm") log_info "  Sugestão: Faça a instalação básica do Proxmox VE." ;;
            "smartctl") log_info "  Sugestão: apt install -y smartmontools" ;;
            "zpool"|"zfs") log_info "  Sugestão: apt install -y zfsutils-linux" ;;
            "journalctl") log_info "  Sugestão: Faz parte do systemd, verifique a instalação." ;;
            "dmesg") log_info "  Sugestão: Faz parte do kmod, verifique a instalação." ;;
            "lsblk") log_info "  Sugestão: apt install -y util-linux" ;;
            "df"|"free") log_info "  Sugestão: apt install -y coreutils" ;;
            "uptime") log_info "  Sugestão: apt install -y procps" ;;
            "nproc") log_info "  Sugestão: apt install -y coreutils" ;;
            "wc") log_info "  Sugestão: apt install -y coreutils" ;;
            "cat") log_info "  Sugestão: apt install -y coreutils" ;;
            "grep") log_info "  Sugestão: apt install -y grep" ;;
            "sed") log_info "  Sugestão: apt install -y sed" ;;
            "awk") log_info "  Sugestão: apt install -y gawk" ;;
        esac
        # Não sai imediatamente aqui, apenas registra o erro, para que o script possa continuar
        # e reportar todas as dependências ausentes antes de um possível exit final.
        EXIT_STATUS=1
    else
        log_success "'$cmd' encontrado."
    fi
done

# Se houver dependências ausentes, aborta aqui.
if [[ $EXIT_STATUS -ne 0 ]]; then
    log_error "Algumas dependências essenciais estão ausentes. Por favor, instale-as e execute o script novamente."
    exit 1
fi

# ========== Validação Inicial das Configurações do Script ==========
log_cabecalho "Validando Configurações do Script"
# Valida IPs de peers
if [[ ${#CLUSTER_PEER_IPS[@]} -eq 0 ]]; then
    log_aviso "Nenhum IP de peer configurado em CLUSTER_PEER_IPS. Testes de comunicação entre nós serão limitados."
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

# Valida IPs de conectividade geral
if [[ ${#GENERAL_CONNECTIVITY_IPS[@]} -eq 0 ]]; then
    log_aviso "Nenhum IP de conectividade geral configurado. Testes de ping básicos serão pulados."
else
    for ip in "${GENERAL_CONNECTIVITY_IPS[@]}"; do
        if ! is_valid_ipv4 "$ip" && ! [[ "$ip" =~ ^[a-zA-Z0-9\.-]+$ ]]; then # Permite IPs ou hostnames
            log_error "Entrada inválida em GENERAL_CONNECTIVITY_IPS: '$ip'. Use um IP válido ou hostname."
            EXIT_STATUS=1
        else
            log_success "Entrada de conectividade geral: $ip (válida)."
        fi
    done
fi

# Valida Portas Essenciais
if [[ ${#ESSENTIAL_PORTS[@]} -eq 0 ]]; then
    log_aviso "Nenhuma porta essencial configurada em ESSENTIAL_PORTS. Testes de portas serão pulados."
else
    for port in "${ESSENTIAL_PORTS[@]}"; do
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
            log_error "Porta inválida configurada em ESSENTIAL_PORTS: '$port'. Por favor, corrija."
            EXIT_STATUS=1
        else
            log_success "Porta essencial configurada: $port (válida)."
        fi
    done
fi

# Aborta se as configurações iniciais estiverem inválidas.
[[ $EXIT_STATUS -ne 0 ]] && { log_error "Por favor, corrija as configurações no script e execute novamente."; exit 1; }

# ========== Execução dos Testes de Ambiente ==========
clear # Limpa a tela para uma saída limpa no terminal.
log_info "🔍 Iniciando Diagnóstico de Ambiente para Proxmox VE - $(date)."
HOSTNAME_LOCAL=$(hostname)
IP_LOCAL=$(hostname -I | awk '{print $1}')
log_info "Hostname local deste nó: $HOSTNAME_LOCAL"
log_info "IP local deste nó: $IP_LOCAL"
echo "----------------------------------------"

# 1. Verificação de Conectividade Geral (Internet/Gateway/NTP)
log_cabecalho "1/12 - Verificando Conectividade Geral (Internet/Gateway/NTP)"
if [[ ${#GENERAL_CONNECTIVITY_IPS[@]} -eq 0 ]]; then
    log_aviso "Testes de conectividade geral pulados (Nenhum IP/Hostname configurado em GENERAL_CONNECTIVITY_IPS)."
else
    for dest in "${GENERAL_CONNECTIVITY_IPS[@]}"; do
        ping_result=$(test_ping_latency "$dest")
        if [[ $? -eq 0 ]]; then
            log_success "  $dest → Latência média: ${ping_result}ms."
        else
            log_error "  $dest → Falha no ping ou timeout. Verifique conectividade externa/gateway."
        fi
    done
fi

# 2. Teste de Resolução DNS (Direta e Reversa)
log_cabecalho "2/12 - Testando Resolução DNS"
# Teste de resolução DNS direta
log_info "  Testando resolução DNS para $DNS_TEST_HOST..."
resolved_ip_dns_test=$(dig +short "$DNS_TEST_HOST" 2>/dev/null)
if [[ -z "$resolved_ip_dns_test" ]]; then
    log_error "  Resolução DNS para '$DNS_TEST_HOST': Falha. Verifique seu servidor DNS em /etc/resolv.conf."
else
    log_success "  Resolução DNS para '$DNS_TEST_HOST': OK ($resolved_ip_dns_test)."
fi

# Teste de resolução DNS reversa para IPs de cluster (apenas se CLUSTER_PEER_IPS estiver definido)
log_info "  Verificando Resolução DNS Reversa para IPs de Cluster:"
if [[ ${#CLUSTER_PEER_IPS[@]} -eq 0 ]]; then
    log_aviso "  Teste de DNS reverso para IPs de cluster pulado (Nenhum IP de peer configurado)."
else
    for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
        check_reverse_dns "$ip_peer"
    done
fi
log_info "  Verificando resolução de hostnames de cluster para IPs:"
for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
    # Tenta resolver o hostname do IP do peer
    peer_hostname=$(dig +short -x "$ip_peer" 2>/dev/null | sed 's/\.$//')
    if [[ -n "$peer_hostname" ]]; then
        check_hostname_resolution "$peer_hostname" "$ip_peer"
    else
        log_aviso "  Não foi possível obter hostname reverso para $ip_peer para teste de resolução. Verifique DNS reverso."
    fi
done


# 3. Verificação de Interface de Rede e MTU
log_cabecalho "3/12 - Verificação de Interface de Rede e MTU"
ip addr show "$PROXMOX_BRIDGE_INTERFACE" &> /dev/null
if [[ $? -eq 0 ]]; then
    log_success "Interface '$PROXMOX_BRIDGE_INTERFACE' existe."
    IP_ATRIBUIDO=$(ip -4 addr show "$PROXMOX_BRIDGE_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [[ -n "$IP_ATRIBUIDO" ]]; then
        log_info "IP atribuído à '$PROXMOX_BRIDGE_INTERFACE': $IP_ATRIBUIDO."
        if [[ "$IP_ATRIBUIDO" != "$IP_LOCAL" ]]; then
             log_aviso "O IP principal da interface '$PROXMOX_BRIDGE_INTERFACE' ($IP_ATRIBUIDO) não coincide com o IP detectado localmente ($IP_LOCAL). Pode indicar um problema."
        fi
    else
        log_error "Interface '$PROXMOX_BRIDGE_INTERFACE' NÃO tem IP IPv4 atribuído. Essencial para o Proxmox."
    fi
    check_mtu
else
    log_error "Interface '$PROXMOX_BRIDGE_INTERFACE' NÃO encontrada. É crítica para a rede do Proxmox."
fi

# 4. Testes de Latência e Portas entre Nós do Cluster
log_cabecalho "4/12 - Testes de Latência e Portas (Comunicação de Cluster)"
if [[ ${#CLUSTER_PEER_IPS[@]} -le 1 ]]; then # Se só tem 1 ou nenhum IP configurado, não é um cluster para testar comunicação entre nós
    log_aviso "Apenas um ou nenhum IP de peer configurado em CLUSTER_PEER_IPS. Testes de comunicação entre nós serão limitados/pulados."
else
    log_info "Medição de Latência entre Nós do Cluster:"
    for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
        if [[ "$ip_peer" != "$IP_LOCAL" ]]; then # Não testa ping para si mesmo se já foi o IP local.
            ping_result=$(test_ping_latency "$ip_peer")
            if [[ $? -eq 0 ]]; then
                log_success "  $ip_peer → Latência média: ${ping_result}ms."
            else
                log_error "  $ip_peer → Falha no ping ou timeout. A comunicação com este nó está comprometida."
            fi
        fi
    done

    log_info "Verificando Portas Essenciais entre Nós do Cluster:"
    if [[ ${#ESSENTIAL_PORTS[@]} -eq 0 ]]; then
        log_aviso "Nenhuma porta essencial configurada. Testes de portas pulados."
    else
        for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
            if [[ "$ip_peer" != "$IP_LOCAL" ]]; then
                log_info "🔧 Verificando Nó $ip_peer (de $IP_LOCAL):"
                for port in "${ESSENTIAL_PORTS[@]}"; do
                    # Assumimos TCP para SSH e WebUI, UDP para Corosync
                    PROTO="tcp"
                    if [[ "$port" -ge 5404 && "$port" -le 5405 ]]; then
                        PROTO="udp"
                    fi

                    # Lógica de verificação para portas UDP do Corosync
                    if [[ "$PROTO" == "udp" && ("$port" == "5404" || "$port" == "5405") ]]; then
                        # Se o cluster está quorate, assumimos que as portas Corosync estão OK
                        if check_corosync_status >/dev/null 2>&1; then # Verifica se o cluster está quorate
                            log_success "  Porta $port ($PROTO) → Acessível (Cluster Corosync OK)."
                        else
                            # Se o cluster não está quorate, o erro é real
                            log_error "  Porta $port ($PROTO) → Bloqueada/Inacessível. ESSENCIAL para comunicação de cluster. Verifique regras de firewall."
                        fi
                    else
                        # Para outras portas TCP/UDP, usa o teste de conectividade padrão
                        if test_port_connectivity "$ip_peer" "$port" "$PROTO"; then
                            log_success "  Porta $port ($PROTO) → Acessível."
                        else
                            log_error "  Porta $port ($PROTO) → Bloqueada/Inacessível. ESSENCIAL para comunicação de cluster. Verifique regras de firewall."
                        fi
                    fi
                done
            fi
        done
    fi
fi

# 5. Verificação de Sincronização de Tempo (NTP)
log_cabecalho "5/12 - Verificação de Sincronização de Tempo (NTP)"
check_ntp_sync

# 6. Verificação dos Serviços Essenciais do Proxmox VE
log_cabecalho "6/12 - Verificando Serviços Essenciais do Proxmox VE"
for servico in "${PROXMOX_SERVICES[@]}"; do
    check_service_status "$servico"
done

# 7. Verificação do Status do Cluster Corosync (se pvecm estiver disponível)
log_cabecalho "7/12 - Verificação do Status do Cluster Corosync"
check_corosync_status # Esta função lida com a ausência de pvecm.

# 8. Verificação de Armazenamento e Discos
check_disk_health

# 9. Análise de Logs do Sistema
check_system_logs

# 10. Verificação de Utilização de Recursos
check_resource_usage

# 11. Verificação de Consistência e Atualizações do Proxmox
check_proxmox_consistency

# 12. Verificação de Configuração de Rede Avançada
check_advanced_network_config


# ========== Checagem de Dependências Essenciais ==========
log_cabecalho "Verificando Dependências Essenciais do Sistema"
REQUIRED_COMMANDS=("ping" "dig" "timeout" "ip" "ss" "systemctl" "awk" "grep" "sed" "lsblk" "df" "free" "uptime" "nproc" "wc")
# Adicionar ntpq ou timedatectl dependendo do que estiver disponível.
if command -v timedatectl >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("timedatectl")
elif command -v ntpq >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("ntpq")
fi
if command -v pvecm >/dev/null 2>&1; then # pvecm só existirá se proxmox já estiver instalado
    REQUIRED_COMMANDS+=("pvecm")
fi
if command -v smartctl >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("smartctl")
fi
if command -v zpool >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("zpool" "zfs")
fi
if command -v journalctl >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("journalctl")
fi
if command -v dmesg >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("dmesg")
fi


for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Dependência ausente: '$cmd' não encontrado. Por favor, instale-a."
        case "$cmd" in
            "ping") log_info "  Sugestão: apt install -y iputils-ping" ;;
            "dig") log_info "  Sugestão: apt install -y dnsutils" ;;
            "timeout") log_info "  Sugestão: apt install -y coreutils" ;;
            "ip") log_info "  Sugestão: apt install -y iproute2" ;;
            "ss") log_info "  Sugestão: apt install -y iproute2" ;;
            "systemctl") log_info "  Sugestão: Faz parte do systemd, se ausente, o sistema está comprometido." ;;
            "timedatectl") log_info "  Sugestão: Faz parte do systemd, verifique a instalação." ;;
            "ntpq") log_info "  Sugestão: apt install -y ntp" ;;
            "pvecm") log_info "  Sugestão: Faça a instalação básica do Proxmox VE." ;;
            "smartctl") log_info "  Sugestão: apt install -y smartmontools" ;;
            "zpool"|"zfs") log_info "  Sugestão: apt install -y zfsutils-linux" ;;
            "journalctl") log_info "  Sugestão: Faz parte do systemd, verifique a instalação." ;;
            "dmesg") log_info "  Sugestão: Faz parte do kmod, verifique a instalação." ;;
            "lsblk") log_info "  Sugestão: apt install -y util-linux" ;;
            "df"|"free") log_info "  Sugestão: apt install -y coreutils" ;;
            "uptime") log_info "  Sugestão: apt install -y procps" ;;
            "nproc") log_info "  Sugestão: apt install -y coreutils" ;;
            "wc") log_info "  Sugestão: apt install -y coreutils" ;;
            "cat") log_info "  Sugestão: apt install -y coreutils" ;;
            "grep") log_info "  Sugestão: apt install -y grep" ;;
            "sed") log_info "  Sugestão: apt install -y sed" ;;
            "awk") log_info "  Sugestão: apt install -y gawk" ;;
        esac
        # Não sai imediatamente aqui, apenas registra o erro, para que o script possa continuar
        # e reportar todas as dependências ausentes antes de um possível exit final.
        EXIT_STATUS=1
    else
        log_success "'$cmd' encontrado."
    fi
done

# Se houver dependências ausentes, aborta aqui.
if [[ $EXIT_STATUS -ne 0 ]]; then
    log_error "Algumas dependências essenciais estão ausentes. Por favor, instale-as e execute o script novamente."
    exit 1
fi

# ========== Validação Inicial das Configurações do Script ==========
log_cabecalho "Validando Configurações do Script"
# Valida IPs de peers
if [[ ${#CLUSTER_PEER_IPS[@]} -eq 0 ]]; then
    log_aviso "Nenhum IP de peer configurado em CLUSTER_PEER_IPS. Testes de comunicação entre nós serão limitados."
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

# Valida IPs de conectividade geral
if [[ ${#GENERAL_CONNECTIVITY_IPS[@]} -eq 0 ]]; then
    log_aviso "Nenhum IP de conectividade geral configurado. Testes de ping básicos serão pulados."
else
    for ip in "${GENERAL_CONNECTIVITY_IPS[@]}"; do
        if ! is_valid_ipv4 "$ip" && ! [[ "$ip" =~ ^[a-zA-Z0-9\.-]+$ ]]; then # Permite IPs ou hostnames
            log_error "Entrada inválida em GENERAL_CONNECTIVITY_IPS: '$ip'. Use um IP válido ou hostname."
            EXIT_STATUS=1
        else
            log_success "Entrada de conectividade geral: $ip (válida)."
        fi
    done
fi

# Valida Portas Essenciais
if [[ ${#ESSENTIAL_PORTS[@]} -eq 0 ]]; then
    log_aviso "Nenhuma porta essencial configurada em ESSENTIAL_PORTS. Testes de portas serão pulados."
else
    for port in "${ESSENTIAL_PORTS[@]}"; do
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
            log_error "Porta inválida configurada em ESSENTIAL_PORTS: '$port'. Por favor, corrija."
            EXIT_STATUS=1
        else
            log_success "Porta essencial configurada: $port (válida)."
        fi
    done
fi

# Aborta se as configurações iniciais estiverem inválidas.
[[ $EXIT_STATUS -ne 0 ]] && { log_error "Por favor, corrija as configurações no script e execute novamente."; exit 1; }

# ========== Execução dos Testes de Ambiente ==========
clear # Limpa a tela para uma saída limpa no terminal.
log_info "🔍 Iniciando Diagnóstico de Ambiente para Proxmox VE - $(date)."
HOSTNAME_LOCAL=$(hostname)
IP_LOCAL=$(hostname -I | awk '{print $1}')
log_info "Hostname local deste nó: $HOSTNAME_LOCAL"
log_info "IP local deste nó: $IP_LOCAL"
echo "----------------------------------------"

# 1. Verificação de Conectividade Geral (Internet/Gateway/NTP)
log_cabecalho "1/12 - Verificando Conectividade Geral (Internet/Gateway/NTP)"
if [[ ${#GENERAL_CONNECTIVITY_IPS[@]} -eq 0 ]]; then
    log_aviso "Testes de conectividade geral pulados (Nenhum IP/Hostname configurado em GENERAL_CONNECTIVITY_IPS)."
else
    for dest in "${GENERAL_CONNECTIVITY_IPS[@]}"; do
        ping_result=$(test_ping_latency "$dest")
        if [[ $? -eq 0 ]]; then
            log_success "  $dest → Latência média: ${ping_result}ms."
        else
            log_error "  $dest → Falha no ping ou timeout. Verifique conectividade externa/gateway."
        fi
    done
fi

# 2. Teste de Resolução DNS (Direta e Reversa)
log_cabecalho "2/12 - Testando Resolução DNS"
# Teste de resolução DNS direta
log_info "  Testando resolução DNS para $DNS_TEST_HOST..."
resolved_ip_dns_test=$(dig +short "$DNS_TEST_HOST" 2>/dev/null)
if [[ -z "$resolved_ip_dns_test" ]]; then
    log_error "  Resolução DNS para '$DNS_TEST_HOST': Falha. Verifique seu servidor DNS em /etc/resolv.conf."
else
    log_success "  Resolução DNS para '$DNS_TEST_HOST': OK ($resolved_ip_dns_test)."
fi

# Teste de resolução DNS reversa para IPs de cluster (apenas se CLUSTER_PEER_IPS estiver definido)
log_info "  Verificando Resolução DNS Reversa para IPs de Cluster:"
if [[ ${#CLUSTER_PEER_IPS[@]} -eq 0 ]]; then
    log_aviso "  Teste de DNS reverso para IPs de cluster pulado (Nenhum IP de peer configurado)."
else
    for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
        check_reverse_dns "$ip_peer"
    done
fi
log_info "  Verificando resolução de hostnames de cluster para IPs:"
for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
    # Tenta resolver o hostname do IP do peer
    peer_hostname=$(dig +short -x "$ip_peer" 2>/dev/null | sed 's/\.$//')
    if [[ -n "$peer_hostname" ]]; then
        check_hostname_resolution "$peer_hostname" "$ip_peer"
    else
        log_aviso "  Não foi possível obter hostname reverso para $ip_peer para teste de resolução. Verifique DNS reverso."
    fi
done


# 3. Verificação de Interface de Rede e MTU
log_cabecalho "3/12 - Verificação de Interface de Rede e MTU"
ip addr show "$PROXMOX_BRIDGE_INTERFACE" &> /dev/null
if [[ $? -eq 0 ]]; then
    log_success "Interface '$PROXMOX_BRIDGE_INTERFACE' existe."
    IP_ATRIBUIDO=$(ip -4 addr show "$PROXMOX_BRIDGE_INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    if [[ -n "$IP_ATRIBUIDO" ]]; then
        log_info "IP atribuído à '$PROXMOX_BRIDGE_INTERFACE': $IP_ATRIBUIDO."
        if [[ "$IP_ATRIBUIDO" != "$IP_LOCAL" ]]; then
             log_aviso "O IP principal da interface '$PROXMOX_BRIDGE_INTERFACE' ($IP_ATRIBUIDO) não coincide com o IP detectado localmente ($IP_LOCAL). Pode indicar um problema."
        fi
    else
        log_error "Interface '$PROXMOX_BRIDGE_INTERFACE' NÃO tem IP IPv4 atribuído. Essencial para o Proxmox."
    fi
    check_mtu
else
    log_error "Interface '$PROXMOX_BRIDGE_INTERFACE' NÃO encontrada. É crítica para a rede do Proxmox."
fi

# 4. Testes de Latência e Portas entre Nós do Cluster
log_cabecalho "4/12 - Testes de Latência e Portas (Comunicação de Cluster)"
if [[ ${#CLUSTER_PEER_IPS[@]} -le 1 ]]; then # Se só tem 1 ou nenhum IP configurado, não é um cluster para testar comunicação entre nós
    log_aviso "Apenas um ou nenhum IP de peer configurado em CLUSTER_PEER_IPS. Testes de comunicação entre nós serão limitados/pulados."
else
    log_info "Medição de Latência entre Nós do Cluster:"
    for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
        if [[ "$ip_peer" != "$IP_LOCAL" ]]; then # Não testa ping para si mesmo se já foi o IP local.
            ping_result=$(test_ping_latency "$ip_peer")
            if [[ $? -eq 0 ]]; then
                log_success "  $ip_peer → Latência média: ${ping_result}ms."
            else
                log_error "  $ip_peer → Falha no ping ou timeout. A comunicação com este nó está comprometida."
            fi
        fi
    done

    log_info "Verificando Portas Essenciais entre Nós do Cluster:"
    if [[ ${#ESSENTIAL_PORTS[@]} -eq 0 ]]; then
        log_aviso "Nenhuma porta essencial configurada. Testes de portas pulados."
    else
        for ip_peer in "${CLUSTER_PEER_IPS[@]}"; do
            if [[ "$ip_peer" != "$IP_LOCAL" ]]; then
                log_info "🔧 Verificando Nó $ip_peer (de $IP_LOCAL):"
                for port in "${ESSENTIAL_PORTS[@]}"; do
                    # Assumimos TCP para SSH e WebUI, UDP para Corosync
                    PROTO="tcp"
                    if [[ "$port" -ge 5404 && "$port" -le 5405 ]]; then
                        PROTO="udp"
                    fi

                    # Lógica de verificação para portas UDP do Corosync
                    if [[ "$PROTO" == "udp" && ("$port" == "5404" || "$port" == "5405") ]]; then
                        # Se o cluster está quorate, assumimos que as portas Corosync estão OK
                        if check_corosync_status >/dev/null 2>&1; then # Verifica se o cluster está quorate
                            log_success "  Porta $port ($PROTO) → Acessível (Cluster Corosync OK)."
                        else
                            # Se o cluster não está quorate, o erro é real
                            log_error "  Porta $port ($PROTO) → Bloqueada/Inacessível. ESSENCIAL para comunicação de cluster. Verifique regras de firewall."
                        fi
                    else
                        # Para outras portas TCP/UDP, usa o teste de conectividade padrão
                        if test_port_connectivity "$ip_peer" "$port" "$PROTO"; then
                            log_success "  Porta $port ($PROTO) → Acessível."
                        else
                            log_error "  Porta $port ($PROTO) → Bloqueada/Inacessível. ESSENCIAL para comunicação de cluster. Verifique regras de firewall."
                        fi
                    fi
                done
            fi
        done
    fi
fi

# 5. Verificação de Sincronização de Tempo (NTP)
log_cabecalho "5/12 - Verificação de Sincronização de Tempo (NTP)"
check_ntp_sync

# 6. Verificação dos Serviços Essenciais do Proxmox VE
log_cabecalho "6/12 - Verificando Serviços Essenciais do Proxmox VE"
for servico in "${PROXMOX_SERVICES[@]}"; do
    check_service_status "$servico"
done

# 7. Verificação do Status do Cluster Corosync (se pvecm estiver disponível)
log_cabecalho "7/12 - Verificação do Status do Cluster Corosync"
check_corosync_status # Esta função lida com a ausência de pvecm.

# 8. Verificação de Armazenamento e Discos
check_disk_health

# 9. Análise de Logs do Sistema
check_system_logs

# 10. Verificação de Utilização de Recursos
check_resource_usage

# 11. Verificação de Consistência e Atualizações do Proxmox
check_proxmox_consistency

# 12. Verificação de Configuração de Rede Avançada
check_advanced_network_config


# ========== Checagem de Dependências Essenciais ==========
log_cabecalho "Verificando Dependências Essenciais do Sistema"
REQUIRED_COMMANDS=("ping" "dig" "timeout" "ip" "ss" "systemctl" "awk" "grep" "sed" "lsblk" "df" "free" "uptime" "nproc" "wc")
# Adicionar ntpq ou timedatectl dependendo do que estiver disponível.
if command -v timedatectl >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("timedatectl")
elif command -v ntpq >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("ntpq")
fi
if command -v pvecm >/dev/null 2>&1; then # pvecm só existirá se proxmox já estiver instalado
    REQUIRED_COMMANDS+=("pvecm")
fi
if command -v smartctl >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("smartctl")
fi
if command -v zpool >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("zpool" "zfs")
fi
if command -v journalctl >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("journalctl")
fi
if command -v dmesg >/dev/null 2>&1; then
    REQUIRED_COMMANDS+=("dmesg")
fi


for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Dependência ausente: '$cmd' não encontrado. Por favor, instale-a."
        case "$cmd" in
            "ping") log_info "  Sugestão: apt install -y iputils-ping" ;;
            "dig") log_info "  Sugestão: apt install -y dnsutils" ;;
            "timeout") log_info "  Sugestão: apt install -y coreutils" ;;
            "ip") log_info "  Sugestão: apt install -y iproute2" ;;
            "ss") log_info "  Sugestão: apt install -y iproute2" ;;
            "systemctl") log_info "  Sugestão: Faz parte do systemd, se ausente, o sistema está comprometido." ;;
            "timedatectl") log_info "  Sugestão: Faz parte do systemd, verifique a instalação." ;;
            "ntpq") log_info "  Sugestão: apt install -y ntp" ;;
            "pvecm") log_info "  Sugestão: Faça a instalação básica do Proxmox VE." ;;
            "smartctl") log_info "  Sugestão: apt install -y smartmontools" ;;
            "zpool"|"zfs") log_info "  Sugestão: apt install -y zfsutils-linux" ;;
            "journalctl") log_info "  Sugestão: Faz parte do systemd, verifique a instalação." ;;
            "dmesg") log_info "  Sugestão: Faz parte do kmod, verifique a instalação." ;;
            "lsblk") log_info "  Sugestão: apt install -y util-linux" ;;
            "df"|"free") log_info "  Sugestão: apt install -y coreutils" ;;
            "uptime") log_info "  Sugestão: apt install -y procps" ;;
            "nproc") log_info "  Sugestão: apt install -y coreutils" ;;
            "wc") log_info "  Sugestão: apt install -y coreutils" ;;
            "cat") log_info "  Sugestão: apt install -y coreutils" ;;
            "grep") log_info "  Sugestão: apt install -y grep" ;;
            "sed") log_info "  Sugestão: apt install -y sed" ;;
            "awk") log_info "  Sugestão: apt install -y gawk" ;;
        esac
        # Não sai imediatamente aqui, apenas registra o erro, para que o script possa continuar
        # e reportar todas as dependências ausentes antes de um possível exit final.
        EXIT_STATUS=1
    else
        log_success "'$cmd' encontrado."
    fi
done

# Se houver dependências ausentes, aborta aqui.
if [[ $EXIT_STATUS -ne 0 ]]; then
    log_error "Algumas dependências essenciais estão ausentes. Por favor, instale-as e execute o script novamente."
    exit 1
fi

# ========== Validação Inicial das Configurações do Script ==========
log_cabecalho "Validando Configurações do Script"
# Valida IPs de peers
if [[ ${#CLUSTER_PEER_IPS[@]} -eq 0 ]]; then
    log_aviso "Nenhum IP de peer configurado em CLUSTER_PEER_IPS. Testes de comunicação entre nós serão limitados."
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

# Valida IPs de conectividade geral
if [[ ${#GENERAL_CONNECTIVITY_IPS[@]} -eq 0 ]]; then
    log_aviso "Nenhum IP de conectividade geral configurado. Testes de ping básicos serão pulados."
else
    for ip in "${GENERAL_CONNECTIVITY_IPS[@]}"; do
        if ! is_valid_ipv4 "$ip" && ! [[ "$ip" =~ ^[a-zA-Z0-9\.-]+$ ]]; then # Permite IPs ou hostnames
            log_error "Entrada inválida em GENERAL_CONNECTIVITY_IPS: '$ip'. Use um IP válido ou hostname."
            EXIT_STATUS=1
        else
            log_success "Entrada de conectividade geral: $ip (válida)."
        fi
    done
fi

# Valida Portas Essenciais
if [[ ${#ESSENTIAL_PORTS[@]} -eq 0 ]]; then
    log_aviso "Nenhuma porta essencial configurada em ESSENTIAL_PORTS. Testes de portas serão pulados."
else
    for port in "${ESSENTIAL_PORTS[@]}"; do
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
            log_error "Porta inválida configurada em ESSENTIAL_PORTS: '$port'. Por favor, corrija."
            EXIT_STATUS=1
        else
            log_success "Porta essencial configurada: $port (válida)."
        fi
    done
fi

# Aborta se as configurações iniciais estiverem inválidas.
[[ $EXIT_STATUS -ne 0 ]] && { log_error "Por favor, corrija as configurações no script e execute novamente."; exit 1; }

# ========== Resumo Final e Análise Detalhada ==========
echo -e "\n${ROXO}📊 ANÁLISE COMPLETA DO DIAGNÓSTICO DO AMBIENTE PROXMOX VE${SEM_COR}"
echo "----------------------------------------"

if [[ $EXIT_STATUS -eq 0 ]]; then
    log_success "TODOS OS TESTES CRÍTICOS PASSARAM!"
    log_info "O ambiente de rede e os serviços essenciais do Proxmox VE parecem estar em bom estado."
    log_info "Recomendação: Prossiga com a instalação/configuração principal do Proxmox VE ou com a manutenção do cluster."
    if [[ ${#AVISO_DETALHES[@]} -gt 0 ]]; then
        echo -e "\n${AMARELO}⚠️  Avisos e Recomendações Adicionais:${SEM_COR}"
        for aviso in "${AVISO_DETALHES[@]}"; do
            echo -e "  - ${AMARELO}${aviso}${SEM_COR}"
        done
        log_info "Revise os avisos para otimizar ou prevenir problemas futuros."
    fi
else
    log_error "PROBLEMAS CRÍTICOS DETECTADOS NA CONFIGURAÇÃO DO AMBIENTE!"
    echo -e "\n${VERMELHO}❌ Problemas Identificados (ITENS DE ALTA PRIORIDADE):${SEM_COR}"
    for erro in "${ERRO_DETALHES[@]}"; do
        echo -e "  - ${VERMELHO}${erro}${SEM_COR}"
    done

    echo -e "\n${AMARELO}⚠️  Avisos e Recomendações (ITENS DE MÉDIA PRIORIDADE):${SEM_COR}"
    if [[ ${#AVISO_DETALHES[@]} -gt 0 ]]; then
        for aviso in "${AVISO_DETALHES[@]}"; do
            echo -e "  - ${AMARELO}${aviso}${SEM_COR}"
        done
    else
        log_info "Nenhum aviso adicional foi identificado."
    fi

    echo -e "\n${CIANO}🛠️ Ações Recomendadas para Resolução:${SEM_COR}"
    echo "  1. **Revise o Firewall:** Se portas essenciais estiverem bloqueadas (Corosync 5404/5405 UDP, SSH 22 TCP, WebUI 8006 TCP), verifique as regras do firewall local (ufw, iptables, Proxmox Firewall) e de qualquer firewall externo na rede."
    echo "  2. **Verifique Conectividade:** Para falhas de ping, teste a conectividade física, configurações de IP/Máscara e gateway."
    echo "  3. **Ajuste o DNS:** Para problemas de resolução DNS, verifique '/etc/resolv.conf' e os registros DNS (A e PTR) no seu servidor DNS."
    echo "  4. **Sincronização de Tempo (NTP):** Garanta que o serviço NTP está ativo e sincronizado. Desvios de tempo causam instabilidade no cluster."
    echo "  5. **Status dos Serviços Proxmox:** Se um serviço estiver inativo, tente iniciá-lo ('systemctl start <servico>') e verifique os logs ('journalctl -xeu <servico>')."
    echo "  6. **Reverta Alterações Recentes:** Se o problema surgiu após uma alteração, tente revertê-la."
    echo -e "\n${VERMELHO}Atenção: Resolva TODOS os problemas marcados com '❌' antes de prosseguir com qualquer configuração crítica no Proxmox VE!${SEM_COR}"
fi
echo "----------------------------------------"

# ========== Limpeza de Logs Antigos ==========
log_info "Realizando limpeza de logs antigos na pasta '$LOG_DIR' (mantendo os últimos $LOG_RETENTION_DAYS dias)..."
find "$LOG_DIR" -type f -name "diagnostico-*.log" -mtime +"$LOG_RETENTION_DAYS" -delete
log_success "Limpeza de logs concluída."

exit "$EXIT_STATUS" # O script sai com 0 para sucesso ou 1 para falha, útil para automação.
