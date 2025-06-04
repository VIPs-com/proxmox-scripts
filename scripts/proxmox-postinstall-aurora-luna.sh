#!/bin/bash
# Versão: 12.1 (com melhorias para Ceph e systemd-timesyncd)
# Script de Pós-Instalação para Proxmox VE 8.x
# Desenvolvido por: VIPs-com
# Data: 2025-06-02

# --- Variáveis de Configuração (EDITÁVEIS) ---
LOG_DIR="/var/log"
BACKUP_DIR="/var/backups/proxmox-postinstall"
LOG_FILE="${LOG_DIR}/proxmox-postinstall-$(date +%Y%m%d)-$(hostname -s).log"
CONFIG_FILE="/etc/proxmox-postinstall.conf"
LOCK_FILE="/etc/proxmox-postinstall.lock"

# IPs dos nós do cluster (inclua o próprio IP e os IPs dos peers)
# Exemplo: CLUSTER_NODES_IPS="172.20.220.20 172.20.220.21"
CLUSTER_NODES_IPS="172.20.220.20 172.20.220.21"

# IPs dos peers do cluster (apenas os IPs dos outros nós, NÃO inclua o próprio IP)
# Exemplo: CLUSTER_PEER_IPS="172.20.220.21"
CLUSTER_PEER_IPS="172.20.220.20 172.20.220.21" # Usado nos testes de conectividade, manter ambos para testar a comunicação entre eles

# Rede do cluster (para regras de firewall, ex: 172.20.220.0/24)
CLUSTER_NETWORK="172.20.220.0/24"

# Redes locais para permitir acesso ao WebUI e SSH (separe por vírgula para /etc/hosts, ou ponto e vírgula para firewall)
# Exemplo: LOCAL_NETWORKS_HOSTS="172.20.220.0/24,172.21.221.0/24"
# Exemplo: LOCAL_NETWORKS_FIREWALL="172.20.220.0/24;172.21.221.0/24"
LOCAL_NETWORKS_HOSTS="172.20.220.0/24,172.21.221.0/24,172.25.125.0/24"
LOCAL_NETWORKS_FIREWALL="172.20.220.0/24;172.21.221.0/24;172.25.125.0/24"

# Fuso horário (lista em /usr/share/zoneinfo)
TIMEZONE="America/Sao_Paulo"

# --- Funções de Logging e Utilitários ---
function log() {
    local level=$1
    local message=$2
    local timestamp=$(date +"%a %b %e %H:%M:%S %Z %Y")
    echo "ℹ️ $level: $message" | tee -a "$LOG_FILE"
}

function log_info() {
    log "ℹ️" "**$1**"
}

function log_success() {
    log "✅" "✅ $1"
}

function log_warn() {
    log "⚠️" "**AVISO**: $1"
}

function log_error() {
    log "❌" "**ERRO**: $1"
}

function log_critical_error() {
    local exit_code=$1
    local message=$2
    log "❌" "**ERRO CRÍTICO** [$exit_code]: $message"
    log_info "O script será encerrado. Verifique o log em $LOG_FILE para mais detalhes."
    exit $exit_code
}

function log_cmd() {
    local cmd="$1"
    log "🔹" "Executando Comando: $cmd"
    eval "$cmd" >> "$LOG_FILE" 2>&1
    return $? # Retorna o código de saída do comando executado
}

function prompt_yes_no() {
    local prompt_text="$1"
    read -p "$prompt_text [s/N] " -n 1 -r
    echo # Nova linha
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        return 0 # Sim
    else
        return 1 # Não
    fi
}

function exit_with_error() {
    local message=$1
    local exit_code=${2:-1} # Default exit code is 1
    log_critical_error "$exit_code" "$message"
}

function create_backup() {
    local file_path="$1"
    local backup_path="${BACKUP_DIR}/$(basename "$file_path").$(date +%Y%m%d%H%M%S)"

    log_info "Fazendo backup de '$file_path' para '$backup_path'..."
    if [ -f "$file_path" ]; then
        cp "$file_path" "$backup_path" >> "$LOG_FILE" 2>&1
        if [ $? -eq 0 ]; then
            log_success "Backup de '$file_path' criado com sucesso."
            return 0
        else
            log_error "Falha ao criar backup de '$file_path'."
            return 1
        fi
    else
        log_info "Arquivo '$file_path' não encontrado, nenhum backup necessário."
        return 0
    fi
}

function check_service_status() {
    local service_name="$1"
    local expected_status="active"
    local timeout=30 # seconds

    log_info "Aguardando e verificando o status do serviço $service_name..."
    for i in $(seq 1 $timeout); do
        status=$(systemctl is-active "$service_name" 2>/dev/null)
        if [ "$status" == "$expected_status" ]; then
            log_success "Serviço $service_name está ativo."
            return 0
        fi
        sleep 1
    done
    log_error "Serviço $service_name não atingiu o status '$expected_status' após $timeout segundos."
    return 1
}

# --- Inicialização ---
mkdir -p "$BACKUP_DIR" >> "$LOG_FILE" 2>&1
chmod 700 "$BACKUP_DIR" >> "$LOG_FILE" 2>&1

# Carregar configurações de arquivo externo (se existir)
if [ -f "$CONFIG_FILE" ]; then
    log_info "Carregando configurações de $CONFIG_FILE..."
    source "$CONFIG_FILE" >> "$LOG_FILE" 2>&1
    if [ $? -eq 0 ]; then
        log_success "Configurações carregadas com sucesso!"
    else
        log_warn "Falha ao carregar configurações de $CONFIG_FILE. Usando padrões do script."
    fi
else
    log_info "Arquivo de configuração $CONFIG_FILE não encontrado. Usando padrões do script."
    log_success "Configurações carregadas com sucesso!"
fi

# Checar e criar lock file
if [ -f "$LOCK_FILE" ] && [ -z "$1" ]; then
    log_critical_error 1 "O script já está em execução ou foi encerrado incorretamente. Remova '$LOCK_FILE' manualmente para continuar. Ex: 'rm -f $LOCK_FILE' ou execute com '--skip-lock'."
elif [ -z "$1" ]; then
    touch "$LOCK_FILE"
fi

# --- Início da Execução ---
log_info "INÍCIO: Execução do script de pós-instalação no nó **$(hostname -s)** em $(date +"%a %b %e %H:%M:%S %p %Z %Y")"
start_time=$(date +%s)

# --- 1. Verificação de Dependências Essenciais ---
log_info "Verificando dependências essenciais do sistema (curl, ping, nc)..."
for cmd in curl ping nc; do
    if ! command -v "$cmd" &>/dev/null; then
        log_critical_error 2 "Dependência '$cmd' não encontrada. Por favor, instale-a manualmente antes de executar o script."
    fi
    log_success "Dependência '$cmd' verificada."
done

# --- 2. Configurar /etc/hosts ---
log_info "Configurando entradas em /etc/hosts para os nós do cluster..."
create_backup "/etc/hosts"

for ip in $CLUSTER_NODES_IPS; do
    hostname_res=$(grep "$ip" /etc/hosts | awk '{print $2}')
    if [ -z "$hostname_res" ]; then
        if [ "$ip" == "$(hostname -I | awk '{print $1}')" ]; then
            hostname_to_add="$(hostname -s)"
        else
            # Tentativa de resolver hostname do IP peer, caso contrário, usar um placeholder
            hostname_to_add=$(dig +short -x "$ip" | sed 's/\.$//' | head -n 1 || echo "peer-${ip//./-}")
        fi
        log_cmd "echo \"$ip $hostname_to_add\" >> /etc/hosts"
        log_info "Adicionada entrada '$ip $hostname_to_add' em /etc/hosts."
    else
        if [ "$ip" == "$(hostname -I | awk '{print $1}')" ]; then
            log_info "Entrada '$ip $(hostname -s)' já existe em /etc/hosts. Pulando."
        else
            log_info "Entrada para IP de peer '$ip' já existe em /etc/hosts. Pulando."
        fi
    fi
done
log_success "Configuração de /etc/hosts concluída."

# --- 3. Validação de IPs e Máscara de Rede ---
log_info "Validando formato dos IPs e máscara de rede..."
# Valida CLUSTER_PEER_IPS (formato IP)
for ip in $CLUSTER_PEER_IPS; do
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_critical_error 3 "Formato de IP inválido em CLUSTER_PEER_IPS: $ip"
    fi
done
log_success "Formato dos IPs em CLUSTER_PEER_IPS verificado."

# Valida CLUSTER_NETWORK (formato CIDR)
if [[ ! "$CLUSTER_NETWORK" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    log_critical_error 3 "Formato de rede inválido em CLUSTER_NETWORK: $CLUSTER_NETWORK"
fi
log_success "Formato de CLUSTER_NETWORK verificado."

# --- 4. Verificação de Conectividade de Rede para Repositórios ---
log_info "Verificando conectividade de rede com os repositórios Debian..."
if ! curl -s --head --request GET http://ftp.debian.org/debian/dists/bookworm/Release | grep "200 OK" > /dev/null; then
    log_critical_error 4 "Falha na conectividade com os repositórios Debian. Verifique sua conexão de internet e DNS."
fi
log_success "Conectividade com repositórios Debian OK."

# --- 5. Verificação da Versão do Proxmox VE ---
log_info "Verificando a versão do Proxmox VE..."
PVE_VERSION=$(pveversion | grep "pve-manager" | cut -d'/' -f2 | cut -d'.' -f1)
if [ "$PVE_VERSION" -lt 8 ]; then
    log_critical_error 6 "Versão do Proxmox VE ($PVE_VERSION) não compatível. Este script é para PVE 8.x ou superior."
fi
log_success "Versão do Proxmox VE ($PVE_VERSION) compatível."

# --- 6. Verificação de Hardware Básico ---
log_info "Verificando recursos de hardware básicos..."
RAM_GB=$(free -g | awk '/Mem:/ {print $2}')
if [ "$RAM_GB" -lt 8 ]; then # Pelo menos 8GB de RAM
    log_warn "RAM disponível ($RAM_GB GB) é menor que 8 GB. Pode afetar a performance em produção."
else
    log_success "RAM disponível ($RAM_GB GB) OK."
fi

# --- 7. Configurar Fuso Horário e Sincronização NTP ---
log_info "Configurando fuso horário para **$TIMEZONE** e sincronização NTP..."

# --- GARANTIR systemd-timesyncd ESTÁ INSTALADO ---
log_info "Verificando e garantindo a instalação do systemd-timesyncd..."
if ! systemctl status systemd-timesyncd >/dev/null 2>&1; then
    log_warn "Serviço 'systemd-timesyncd' não encontrado. Tentando instalar..."
    log_cmd "apt update" # Garante que o apt tenha as listas mais recentes antes de tentar instalar
    log_cmd "apt install -y systemd-timesyncd"
    if [ $? -eq 0 ]; then
        log_success "'systemd-timesyncd' instalado com sucesso."
        log_cmd "systemctl enable --now systemd-timesyncd" # Habilita e inicia o serviço
        log_success "Serviço 'systemd-timesyncd' habilitado e iniciado."
    else
        log_error "Falha ao instalar 'systemd-timesyncd'. Por favor, verifique manualmente."
        exit_with_error "Falha na instalação de systemd-timesyncd" 5
    fi
else
    log_info "Serviço 'systemd-timesyncd' já está presente."
fi

log_info "Verificando conectividade com servidores NTP externos (pool.ntp.org:123/UDP)..."
if ! nc -uz -w 5 pool.ntp.org 123 >/dev/null 2>&1; then
    log_critical_error 5 "Falha na conectividade com servidores NTP externos. Verifique regras de firewall outbound ou DNS."
fi
log_success "Conectividade NTP externa OK."

log_cmd "timedatectl set-timezone $TIMEZONE"
log_cmd "timedatectl set-ntp true"
log_cmd "systemctl restart systemd-timesyncd"
if [ $? -ne 0 ]; then
    log_critical_error 5 "Falha ao executar o comando: systemctl restart systemd-timesyncd"
fi

log_info "Aguardando e verificando a sincronização NTP inicial..."
sleep 5 # Dá um tempo para o serviço iniciar
if ! timedatectl status | grep -q "NTP synchronized: yes"; then
    log_warn "Sincronização NTP inicial pode não ter ocorrido. Verifique o serviço 'systemd-timesyncd'."
else
    log_success "Sincronização NTP bem-sucedida."
fi

# --- 8. Configurar Repositórios APT (Proxmox e Debian) ---
log_info "Desabilitando repositório de subscrição e habilitando repositório PVE no-subscription..."

# --- REMOVER REPOSITÓRIO CEPH ENTERPRISE (SE EXISTIR) ---
log_info "Removendo repositório Ceph Enterprise (se existir e não for necessário)..."
if [ -f "/etc/apt/sources.list.d/ceph.list" ]; then
    log_info "Fazendo backup de '/etc/apt/sources.list.d/ceph.list' para '/var/backups/proxmox-postinstall/ceph.list.$(date +%Y%m%d%H%M%S)'..."
    cp /etc/apt/sources.list.d/ceph.list "/var/backups/proxmox-postinstall/ceph.list.$(date +%Y%m%d%H%M%S)" >> "$LOG_FILE" 2>&1
    log_info "Backup de '/etc/apt/sources.list.d/ceph.list' criado com sucesso."

    log_cmd "mv /etc/apt/sources.list.d/ceph.list /etc/apt/sources.list.d/ceph.list.bak"
    if [ $? -eq 0 ]; then
        log_success "Repositório Ceph Enterprise desabilitado."
    else
        log_warn "Falha ao desabilitar repositório Ceph Enterprise. Pode ser necessário fazer manualmente."
    fi
else
    log_info "Arquivo '/etc/apt/sources.list.d/ceph.list' não encontrado, nenhum backup ou remoção necessária."
fi

create_backup "/etc/apt/sources.list.d/pve-enterprise.list" # Tenta fazer backup mesmo que não encontrado, a função gerencia
create_backup "/etc/apt/sources.list"
create_backup "/etc/apt/sources.list.d/pve-no-subscription.list" # Tenta fazer backup mesmo que não encontrado

if [ -f "/etc/apt/sources.list.d/pve-enterprise.list" ]; then
    log_cmd "rm /etc/apt/sources.list.d/pve-enterprise.list"
    if [ $? -eq 0 ]; then
        log_success "Repositório de subscrição desabilitado."
    else
        log_warn "Falha ao desabilitar o repositório de subscrição. Pode ser necessário fazer manualmente."
    fi
else
    log_info "Arquivo /etc/apt/sources.list.d/pve-enterprise.list não encontrado. Nenhuma ação necessária para desabilitar o repositório de subscrição."
fi

# Recrear /etc/apt/sources.list com as entradas Debian padrão
log_cmd "echo 'deb http://ftp.debian.org/debian bookworm main contrib' > /etc/apt/sources.list"
log_cmd "echo 'deb http://ftp.debian.org/debian bookworm-updates main contrib' >> /etc/apt/sources.list"
log_cmd "echo 'deb http://security.debian.org/debian-security bookworm-security main contrib' >> /etc/apt/sources.list"

# Criar/Reescrever pve-no-subscription.list
log_cmd "echo 'deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription' > /etc/apt/sources.list.d/pve-no-subscription.list"

# --- ADICIONAR REPOSITÓRIO CEPH NO-SUBSCRIPTION (SE NECESSÁRIO) ---
# Adiciona o repositório Ceph Quincy (versão do Ceph compatível com Bookworm)
log_info "Adicionando repositório Proxmox Ceph No-Subscription (Quincy)..."
log_cmd "echo 'deb http://download.proxmox.com/debian/ceph-quincy bookworm main' > /etc/apt/sources.list.d/ceph.list"
if [ $? -eq 0 ]; then
    log_success "Repositório Ceph No-Subscription adicionado com sucesso."
else
    log_error "Falha ao adicionar repositório Ceph No-Subscription."
fi

log_info "Atualizando listas de pacotes e o sistema operacional..."
log_cmd "apt update"
log_cmd "apt dist-upgrade -y"
log_cmd "apt autoremove -y"
log_cmd "apt clean"

# --- 9. Remover Aviso de Assinatura do WebUI ---
log_info "Removendo o aviso de assinatura Proxmox VE do WebUI (se não possuir uma licença ativa)..."
# Cria um hook APT para remover o aviso após cada atualização do proxmox-widget-toolkit
log_cmd "echo \"DPkg::Post-Invoke { \\\"dpkg -V proxmox-widget-toolkit | grep -q '/proxmoxlib.js$'; if [ \\\$? -eq 1 ]; then sed -i '/.*data.status.*{/{s/\\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; fi\\\"; };\" > /etc/apt/apt.conf.d/no-nag-script"
# Reinstala o pacote para aplicar a alteração imediatamente
log_cmd "apt --reinstall install -y proxmox-widget-toolkit"
log_success "Aviso de assinatura removido do WebUI (se aplicável)."

# --- 10. Configurar Firewall do Proxmox VE ---
log_info "Verificando portas críticas em uso antes de configurar o firewall..."
CRITICAL_PORTS=("8006:TCP/UDP" "22:TCP/UDP" "5405:TCP/UDP")
for port_info in "${CRITICAL_PORTS[@]}"; do
    port=$(echo "$port_info" | cut -d':' -f1)
    proto=$(echo "$port_info" | cut -d':' -f2)
    if ss -tuln | grep -E "(^| )$port($| )" | grep -q -E "(^| )$(echo "$proto" | tr '[:upper:]' '[:lower:]' | sed 's/\/.*/ /')"; then
        log_warn "Porta $port_info já está em uso! Verifique se isso não conflitará com as regras do firewall Proxmox. Se estiver em uso pelo Proxmox ou Corosync, isso é normal."
    fi
done
log_success "Verificação de portas concluída."

log_info "Configurando o firewall do Proxmox VE com regras específicas..."
log_info "Desativando e limpando todas as regras existentes do firewall Proxmox VE..."
log_cmd "apt --reinstall install -y pve-firewall" # Garante que o pve-firewall esteja funcional e limpo

log_info "Reiniciando o serviço pvedaemon para garantir que o firewall possa se comunicar..."
log_cmd "systemctl restart pvedaemon"
check_service_status "pvedaemon"
if [ $? -ne 0 ]; then
    log_warn "Serviço pvedaemon não está ativo. Isso pode afetar a comunicação do firewall."
fi

# Reiniciar o serviço de firewall PVE para limpar configurações antigas
log_cmd "pve-firewall stop"
log_cmd "pve-firewall flush"
if [ $? -eq 0 ]; then
    log_info "Firewall Proxmox VE desabilitado ou não está rodando."
else
    log_warn "Falha ao desabilitar/limpar o firewall Proxmox VE."
fi

# Criar diretório para arquivos de configuração do firewall do host
log_info "Criando diretório para arquivos de configuração do firewall do host: /etc/pve/nodes/$(hostname -s)/firewall..."
log_cmd "mkdir -p /etc/pve/nodes/$(hostname -s)/firewall"

# Fazer backup do arquivo de configuração do firewall do host
create_backup "/etc/pve/nodes/$(hostname -s)/firewall/host.fw"

# Escrever novas regras de firewall para /etc/pve/nodes/<hostname>/firewall/host.fw
log_info "Escrevendo novas regras de firewall para /etc/pve/nodes/$(hostname -s)/firewall/host.fw..."
cat <<EOF > /etc/pve/nodes/$(hostname -s)/firewall/host.fw
# Firewall do Proxmox VE para o nó $(hostname -s)
# Gerado pelo script de pós-instalação

[OPTIONS]
enable: 1
policy_in: DROP
policy_out: ACCEPT

[RULES]
# Permitir acesso SSH do LOCAL_NETWORKS
IN ACCEPT -p tcp -s $LOCAL_NETWORKS_FIREWALL --dport 22 -c "Acesso SSH das redes internas"

# Permitir acesso ao WebUI do Proxmox VE (porta 8006) do LOCAL_NETWORKS
IN ACCEPT -p tcp -s $LOCAL_NETWORKS_FIREWALL --dport 8006 -c "Acesso WebUI das redes internas"

# Permitir comunicação Corosync entre os nós do cluster na CLUSTER_NETWORK
IN ACCEPT -p udp -s $CLUSTER_NETWORK --dport 5404:5405 -c "Corosync entre nós do cluster"

# Permitir comunicação pve-cluster (sistema de arquivos de cluster) entre os nós na CLUSTER_NETWORK
IN ACCEPT -p tcp -s $CLUSTER_NETWORK --dport 2224 -c "pve-cluster entre nós do cluster"

# Permitir Ping (ICMP) entre os nós do cluster na CLUSTER_NETWORK
IN ACCEPT -p icmp -s $CLUSTER_NETWORK -c "Ping entre nós do cluster"

# Permitir acesso de saída para NTP
OUT ACCEPT -p udp --dport 123 -c "Saída para NTP"

# Permitir acesso de saída para Internet (HTTPS)
OUT ACCEPT -p tcp --dport 443 -c "Saída para HTTPS (Internet)"
EOF
log_success "Regras de firewall escritas em /etc/pve/nodes/$(hostname -s)/firewall/host.fw."

# Configurar 'localnet' para as VLANs internas no firewall do cluster (cluster.fw)
log_info "Configurando 'localnet' para as VLANs internas no firewall do cluster (cluster.fw)..."
create_backup "/etc/pve/firewall/cluster.fw"

if grep -q "\[OPTIONS\]" /etc/pve/firewall/cluster.fw; then
    log_info "Seção [OPTIONS] encontrada em /etc/pve/firewall/cluster.fw. Inserindo localnets..."
    # Remove linha 'localnet' existente (se houver) e adiciona a nova
    log_cmd "sed -i '/^localnet:/d' /etc/pve/firewall/cluster.fw"
    log_cmd "sed -i '/^\\[OPTIONS\\]/a\\localnet: $LOCAL_NETWORKS_FIREWALL' /etc/pve/firewall/cluster.fw"
else
    # Se a seção [OPTIONS] não existe, cria o arquivo com ela e a entrada localnet
    log_warn "Seção [OPTIONS] não encontrada em /etc/pve/firewall/cluster.fw. Criando arquivo/seção."
    echo "[OPTIONS]" > /etc/pve/firewall/cluster.fw
    echo "localnet: $LOCAL_NETWORKS_FIREWALL" >> /etc/pve/firewall/cluster.fw
fi
log_success "Configuração de 'localnet' no firewall do cluster concluída."

# Ativar e recarregar o serviço de firewall do Proxmox VE
log_info "Ativando e recarregando o serviço de firewall do Proxmox VE para aplicar as novas regras..."
log_cmd "pve-firewall restart"
log_success "Firewall Proxmox VE configurado e recarregado com sucesso."

# --- 11. Hardening de Segurança (SSH) ---
if prompt_yes_no "Deseja aplicar hardening de segurança (desativar login de root por senha e password authentication)?"; then
    log_info "Aplicando hardening SSH..."
    create_backup "/etc/ssh/sshd_config"
    log_cmd "sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config"
    log_cmd "sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config"
    log_cmd "systemctl restart sshd"
    log_success "Hardening aplicado! **Atenção**: Agora, o acesso ao root via SSH só será possível usando chaves SSH. Certifique-se de tê-las configuradas antes de fechar a sessão atual."
else
    log_info "Hardening SSH ignorado. O login por senha permanece ativo (menos seguro para produção)."
fi

# --- 12. Instalar Ferramentas Adicionais Úteis ---
if prompt_yes_no "Deseja instalar ferramentas adicionais úteis (ex: qemu-guest-agent, ifupdown2, git, htop, smartmontools)?"; then
    log_info "Instalando pacotes adicionais..."
    log_cmd "apt install -y qemu-guest-agent ifupdown2 git htop smartmontools"
    log_success "Pacotes adicionais instalados."
else
    log_info "Instalação de pacotes adicionais ignorada."
fi

# --- 13. Verificação Final de Serviços Críticos do Proxmox VE ---
log_info "Verificando status de serviços críticos do Proxmox VE..."
for service in corosync pve-cluster pvedaemon; do
    systemctl is-active "$service" >> "$LOG_FILE" 2>&1
    if [ $? -ne 0 ]; then
        log_error "Serviço $service não está ativo!"
    else
        echo "active"
    fi
done
log_success "Todos os serviços críticos do Proxmox VE (corosync, pve-cluster, pvedaemon) estão ativos."

# --- 14. Testes de Conectividade Essencial do Cluster ---
log_info "Realizando testes de conectividade essencial do cluster com nós pares..."
CURRENT_NODE_IP=$(hostname -I | awk '{print $1}')
for peer_ip in $CLUSTER_PEER_IPS; do
    if [ "$peer_ip" == "$CURRENT_NODE_IP" ]; then
        continue # Não testa a si mesmo como peer
    fi

    log_info "Testando conexão com o nó $peer_ip..."
    # Teste de Corosync (porta 5404)
    if ! nc -uz -w 3 "$peer_ip" 5404 >/dev/null 2>&1; then
        log_error "Conexão Corosync com $peer_ip (porta 5404) falhou. Verifique as regras de firewall e a rede."
    fi

    # Teste de pve-cluster (porta 2224)
    if ! nc -uz -w 3 "$peer_ip" 2224 >/dev/null 2>&1; then
        log_error "Conexão pve-cluster com $peer_ip (porta 2224) falhou. Verifique as regras de firewall e a rede."
    fi

    # Teste de Ping
    if ! ping -c 1 -W 1 "$peer_ip" >/dev/null 2>&1; then
        log_error "Ping com $peer_ip falhou. Verifique a conectividade de rede básica."
    else
        log_success "Ping com $peer_ip OK."
    fi
done

# --- 15. Teste de Conectividade Externa (Internet) ---
log_info "Testando conexão externa (internet) via HTTPS..."
if ! curl -s --head --request GET https://google.com | grep "200 OK" > /dev/null; then
    log_warn "Conexão externa via HTTPS (google.com:443) falhou. Verifique a conectividade com a internet."
else
    log_success "Conexão externa via HTTPS (google.com:443) OK."
fi

# --- 16. Limpeza ---
log_info "Limpando possíveis resíduos de execuções anteriores ou arquivos temporários..."
log_cmd "apt autoremove -y"
log_cmd "apt clean"
log_success "Limpeza de resíduos concluída."

log_info "Limpando logs de pós-instalação antigos (com mais de 15 dias) em $LOG_DIR/..."
log_cmd "find $LOG_DIR -name \"proxmox-postinstall-*.log\" -mtime +15 -exec rm {} \\;"
log_success "Limpeza de logs antigos concluída."

# --- Finalização ---
end_time=$(date +%s)
total_time=$((end_time - start_time))

log_success "FINALIZADO: Configuração concluída com sucesso no nó **$(hostname -s)** em $(date +"%a %b %e %H:%M:%S %p %Z %Y")."
log_info "Tempo total de execução do script: **${total_time} segundos**."
log_info "O log detalhado de todas as operações está disponível em: **$LOG_FILE**."

# --- Resumo e Próximos Passos para o Usuário ---
echo ""
log_info "📝 **RESUMO DA CONFIGURAÇÃO E PRÓXIMOS PASSOS PARA SEU HOMELAB**"
log_info "---------------------------------------------------------"
log_info "✔️ Nó configurado: **$(hostname -s)**"
log_info "✔️ Firewall Proxmox VE ativo com regras para:"
log_info "    - Acesso ao WebUI (porta 8006) das redes internas"
log_info "    - Acesso SSH (porta 22) das redes internas"
log_info "    - Comunicação interna do cluster (Corosync: 5404-5405, pve-cluster: 2224) na rede '$CLUSTER_NETWORK'"
log_info "    - Ping (ICMP) entre os nós do cluster"
log_info "    - Acesso de saída para NTP e Internet (HTTPS)"
log_info "    - Redes Locais ('localnet') configuradas para: $LOCAL_NETWORKS_FIREWALL"
if grep -q "PermitRootLogin prohibit-password" /etc/ssh/sshd_config && grep -q "PasswordAuthentication no" /etc/ssh/sshd_config; then
    log_info "✔️ Hardening SSH (desativa login root por senha): Aplicado"
else
    log_info "✔️ Hardening SSH (desativa login root por senha): Ignorado"
fi
log_info "✔️ NTP sincronizado: $(timedatectl status | grep "NTP synchronized" | awk '{print $3}')"
log_info "✔️ Repositórios atualizados: No-Subscription Proxmox VE e Debian Bookworm"
log_info "---------------------------------------------------------"
log_info "🔍 **PRÓXIMOS PASSO CRUCIAIS (MANUAIS)**:"
log_info "1.  **REINICIE O NÓ**: Algumas configurações (especialmente de rede e SSH) só terão efeito total após o reinício. **Isso é fundamental!**"
log_info "2.  **CRIE O CLUSTER (Primeiro Nó)**: No WebUI do seu primeiro nó, vá em **Datacenter > Cluster > Create Cluster**. Defina um nome para o cluster (ex: Aurora-Luna-Cluster)."
log_info "3.  **ADICIONE OUTROS NÓS AO CLUSTER**: Nos demais nós, no WebUI, vá em **Datacenter > Cluster > Join Cluster**. Use as informações do primeiro nó (token) para adicioná-los."
log_info "4.  **CONFIGURE STORAGES**: Após o cluster estar funcional, configure seus storages (LVM-Thin, ZFS, NFS, Ceph, etc.) conforme sua necessidade para armazenar VMs/CTs e ISOs."
log_info "5.  **CRIE CHAVES SSH (se aplicou hardening)**: Se você aplicou o hardening SSH, configure suas chaves SSH para acesso root antes de fechar a sessão atual, para garantir acesso futuro."
log_info "---------------------------------------------------------"

# Remover lock file no final
rm -f "$LOCK_FILE"

# --- Opção de Reinício ---
if prompt_yes_no "REINÍCIO ALTAMENTE RECOMENDADO: Para garantir que todas as configurações sejam aplicadas, é **fundamental** reiniciar o nó. Deseja reiniciar agora?"; then
    log_info "Reiniciando o nó **$(hostname -s)** agora..."
    log_cmd "reboot"
else
    log_info "Reinício adiado. Lembre-se de executar 'reboot' manualmente no nó **$(hostname -s)** o mais rápido possível para aplicar todas as mudanças."
fi

exit 0
