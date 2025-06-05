#!/usr/bin/env bash

# 🛡️ Script de Configuração de Firewall Proxmox VE (V.1.0.0)
# Este script configura as regras de firewall para um nó Proxmox VE.
# Ele deve ser executado INDIVIDUALMENTE em cada nó do cluster APÓS a configuração inicial do nó.

# 🛠️ Configurações Essenciais - Podem ser sobrescritas por /etc/proxmox-firewall.conf
NODE_NAME=$(hostname)             # Nome do servidor atual
CLUSTER_NETWORK="172.20.220.0/24" # Rede para comunicação interna do cluster (Corosync, pve-cluster)

# Redes locais que terão acesso permitido ao WebUI e SSH.
# Estas redes serão agrupadas em um IPSet chamado 'local_networks'.
LOCAL_NETWORKS=("172.20.220.0/24" "172.21.221.0/24" "172.25.125.0/24")

LOG_FILE="/var/log/proxmox-firewall-$(date +%Y%m%d)-$(hostname).log" # Arquivo de log específico por nó
LOCK_FILE="/etc/proxmox-firewall.lock" # Garante que o script não seja executado múltiplas vezes
START_TIME=$(date +%s)            # Início do registro de tempo de execução

# --- FUNÇÕES AUXILIARES ---

# Funções de Log
log_info() { echo -e "\nℹ️ $*" | tee -a "$LOG_FILE"; }
log_ok() { echo -e "\n✅ $*" | tee -a "$LOG_FILE"; }
log_erro() { echo -e "\n❌ **ERRO**: $*" | tee -a "$LOG_FILE"; }

log_cmd() {
    echo -e "\n🔹 Executando Comando: $*" | tee -a "$LOG_FILE"
    eval "$@" >> "$LOG_FILE" 2>&1
    local status=$?
    if [ $status -ne 0 ]; then
        echo "❌ **ERRO CRÍTICO** [$status]: Falha ao executar o comando: $*" | tee -a "$LOG_FILE"
        echo "O script será encerrado. Verifique o log em $LOG_FILE para mais detalhes." | tee -a "$LOG_FILE"
        exit $status
    fi
    return $status
}

# Função para fazer backup de arquivos
backup_file() {
    local file="$1"
    if [ -f "$file" ]; then
        local backup_dir="/var/backups/proxmox-firewall"
        mkdir -p "$backup_dir"
        local timestamp=$(date +%Y%m%d%H%M%S)
        local backup_path="$backup_dir/$(basename "$file").${timestamp}"
        log_info "📦 Fazendo backup de '$file' para '$backup_path'..."
        cp -p "$file" "$backup_path" >> "$LOG_FILE" 2>&1
        if [ $? -ne 0 ]; then
            log_info "⚠️ **AVISO**: Falha ao criar backup de '$file'. Continue com cautela."
        else
            log_info "✅ Backup de '$file' criado com sucesso."
        fi
    else
        log_info "ℹ️ Arquivo '$file' não encontrado, nenhum backup necessário."
    fi
}

# Função para exibir ajuda
show_help() {
    echo "Uso: $0 [OPÇÃO]"
    echo "Script para configuração de firewall em um nó Proxmox VE."
    echo ""
    echo "Opções:"
    echo "  -h, --help    Mostra esta mensagem de ajuda e sai."
    echo "  --skip-lock   Ignora a verificação de arquivo de lock, permitindo múltiplas execuções (NÃO RECOMENDADO)."
    echo ""
    echo "Variáveis de configuração podem ser definidas em /etc/proxmox-firewall.conf"
    echo "Exemplo: CLUSTER_NETWORK=\"192.168.1.0/24\""
    echo "         LOCAL_NETWORKS=(\"192.168.1.0/24\" \"10.0.0.0/8\")"
    exit 0
}

# --- PROCESSAMENTO DE OPÇÕES E CARREGAMENTO DE CONFIGURAÇÃO EXTERNA ---

# Processa opções de linha de comando
SKIP_LOCK=false
for arg in "$@"; do
    case "$arg" in
        -h|--help) show_help ;;
        --skip-lock) SKIP_LOCK=true ;;
        *) log_erro "Opção inválida: $arg. Use -h ou --help para ver as opções."; exit 1 ;;
    esac
done

# --- DOWNLOAD E CARREGAMENTO DE CONFIGURAÇÃO EXTERNA ---
CONFIG_URL="https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/etc/proxmox-firewall.conf" # URL para o arquivo de config do firewall
CONFIG_FILE="/etc/proxmox-firewall.conf"

# Se o arquivo de configuração local não existir, baixa do GitHub
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_info "⚙️ Arquivo de configuração do firewall não encontrado localmente. Tentando baixar do GitHub: $CONFIG_URL..."
    curl -s -o "$CONFIG_FILE" "$CONFIG_URL"
    if [ $? -eq 0 ] && [ -f "$CONFIG_FILE" ]; then
        log_ok "✅ Configuração do firewall baixada e salva em $CONFIG_FILE."
    else
        log_erro "Falha ao baixar configurações do firewall do GitHub! Verifique a URL ou conectividade. Continuando com configurações padrão do script."
        rm -f "$CONFIG_FILE"
    fi
fi

# Carrega configurações do arquivo (local ou recém-baixado)
if [[ -f "$CONFIG_FILE" ]]; then
    log_info "⚙️ Carregando configurações do firewall de $CONFIG_FILE..."
    source "$CONFIG_FILE"
    log_ok "✅ Configurações do firewall carregadas com sucesso!"
else
    log_info "ℹ️ Arquivo de configuração do firewall $CONFIG_FILE não encontrado. Usando configurações padrão do script."
fi

# --- INÍCIO DA EXECUÇÃO DO SCRIPT ---

# 🔒 Prevenção de Múltiplas Execuções
if [[ "$SKIP_LOCK" == "false" && -f "$LOCK_FILE" ]]; then
    log_erro "O script de firewall já foi executado anteriormente neste nó ($NODE_NAME). Abortando para evitar configurações duplicadas."
    log_info "Se você realmente precisa re-executar, remova '$LOCK_FILE' ou use '--skip-lock' (NÃO RECOMENDADO)."
    exit 1
fi
touch "$LOCK_FILE" # Cria o arquivo de lock

log_info "📅 **INÍCIO**: Execução do script de configuração de firewall no nó **$NODE_NAME** em $(date)"

# --- Fase 1: Verificações Iniciais ---

log_info "🔍 Verificando dependências essenciais do sistema (pve-firewall)..."
if ! command -v pve-firewall &>/dev/null; then
    log_erro "O comando 'pve-firewall' não foi encontrado. Certifique-se de que o Proxmox VE está instalado corretamente."
    exit 1
fi
log_info "✅ Dependência 'pve-firewall' verificada."

log_info "🔍 Verificando portas críticas em uso antes de configurar o firewall..."
# Lista de portas essenciais para Proxmox e cluster
CRITICAL_PORTS="8006 22 5404 5405 2224"
for port in $CRITICAL_PORTS; do
    if ss -tuln | grep -q ":$port "; then
        log_info "⚠️ **AVISO**: Porta TCP/UDP **$port** já está em uso! Verifique se isso não conflitará com as regras do firewall Proxmox. Se estiver em uso pelo Proxmox ou Corosync, isso é normal."
    fi
done
log_info "✅ Verificação de portas concluída."

# --- Fase 2: Configuração do Firewall ---

log_info "🛡️ Configurando o firewall do Proxmox VE com regras específicas..."

# Tentativa de resetar o firewall para um estado limpo
log_info "Desativando e limpando todas as regras existentes do firewall Proxmox VE..."
# Reinstala o pacote pve-firewall para garantir que esteja em um estado limpo
log_cmd "apt --reinstall install -y pve-firewall"

# Reinicia pvedaemon, pois pve-firewall depende dele
log_info "Reiniciando o serviço pvedaemon para garantir que o firewall possa se comunicar..."
log_cmd "systemctl restart pvedaemon"
log_info "Aguardando 5 segundos para pvedaemon iniciar..."
sleep 5

# Verifica se pvedaemon está ativo
if ! systemctl is-active pvedaemon; then
    log_erro "O serviço pvedaemon NÃO está ativo após o reinício. O script será encerrado."
    exit 1
else
    log_ok "✅ Serviço pvedaemon está ativo."
fi

# Verifica se o firewall está habilitado e desabilita
if pve-firewall status | grep -q "Status: enabled"; then
    log_info "O firewall Proxmox VE está habilitado. Desativando-o temporariamente."
    log_cmd "pve-firewall disable"
else
    log_info "O firewall Proxmox VE já está desabilitado ou não está rodando."
fi

# --- Início da lógica de configuração do firewall via host.fw e cluster.fw (com IPSet) ---
FIREWALL_DIR="/etc/pve/nodes/$NODE_NAME/firewall"
HOST_FW_FILE="$FIREWALL_DIR/host.fw"
CLUSTER_FW_FILE="/etc/pve/firewall/cluster.fw" # Caminho para o cluster.fw

log_info "Criando diretório para arquivos de configuração do firewall do host: $FIREWALL_DIR..."
log_cmd "mkdir -p $FIREWALL_DIR"

log_info "Fazendo backup do arquivo de configuração do firewall do host: $HOST_FW_FILE..."
backup_file "$HOST_FW_FILE"

log_info "Fazendo backup do arquivo de configuração do firewall do cluster: $CLUSTER_FW_FILE..."
backup_file "$CLUSTER_FW_FILE"

# Configurando 'local_networks' como um IPSet no cluster.fw
log_info "Configurando IPSet 'local_networks' no firewall do cluster ($CLUSTER_FW_FILE)..."
# Primeiro, limpa o conteúdo existente de cluster.fw para evitar duplicações e erros de parsing antigos
log_cmd "echo '' > $CLUSTER_FW_FILE" # Limpa o arquivo

cat <<EOF >> "$CLUSTER_FW_FILE"
[OPTIONS]
enable: 1 # Habilita o firewall do cluster (globalmente)

[IPSET local_networks]
$(IFS=$'\n'; echo "${LOCAL_NETWORKS[*]}")
EOF
log_ok "✅ IPSet 'local_networks' configurado em $CLUSTER_FW_FILE."


log_info "Escrevendo novas regras de firewall para $HOST_FW_FILE (usando IPSet)..."
# Inicia o arquivo com as opções padrão e política de DROP para entrada
cat <<EOF > "$HOST_FW_FILE"
# firewall for host $NODE_NAME
#
[OPTIONS]
enable: 1
policy_in: DROP
policy_out: ACCEPT

[RULES]
# Regras para permitir acesso ao WebUI (porta 8006) e SSH (porta 22) das redes locais
IN ACCEPT -p tcp -s +local_networks --dport 8006 -j ACCEPT -c "Acesso WebUI das redes locais"
IN ACCEPT -p tcp -s +local_networks --dport 22 -j ACCEPT -c "Acesso SSH das redes locais"

# CRÍTICO: Regras para comunicação INTERNA DO CLUSTER (Corosync e pve-cluster)
IN ACCEPT -p udp -s $CLUSTER_NETWORK --dport 5404:5405 -j ACCEPT -c "Corosync entre nós do cluster"
IN ACCEPT -p tcp -s $CLUSTER_NETWORK --dport 2224 -j ACCEPT -c "pve-cluster entre nós do cluster"

# Permitir tráfego ICMP (ping) entre os nós do cluster para facilitar diagnósticos
IN ACCEPT -p icmp -s $CLUSTER_NETWORK -j ACCEPT -c "Permitir ping entre os nós do cluster"

# Regra para permitir tráfego de SAÍDA para NTP (servidores externos)
OUT ACCEPT -p udp --dport 123 -j ACCEPT -c "Permitir saída para NTP"

# A política padrão de entrada (policy_in: DROP) já bloqueia o tráfego não explicitamente permitido.
# A política padrão de saída (policy_out: ACCEPT) permite a saída por padrão.
EOF
log_ok "✅ Regras de firewall escritas em $HOST_FW_FILE (usando IPSet)."

log_info "Ativando e recarregando o serviço de firewall do Proxmox VE para aplicar as novas regras..."
log_cmd "pve-firewall start" # Este comando habilita e inicia o firewall
log_cmd "pve-firewall reload" # Usar reload para aplicar as novas regras do host.fw e cluster.fw
log_ok "✅ Firewall Proxmox VE configurado e recarregado com sucesso."

# --- Fim da lógica de configuração do firewall ---

# --- Fase 3: Finalização ---

log_info "🔍 Verificando status do serviço de firewall do Proxmox VE..."
if ! systemctl is-active pve-firewall; then
    log_erro "O serviço pve-firewall NÃO está ativo. Verifique os logs e tente reiniciar manualmente."
    log_info "O script será encerrado devido à falha de serviço crítico."
    exit 1
else
    log_ok "✅ Serviço pve-firewall está ativo."
fi

log_info "🔗 Realizando testes de conectividade externa (internet) via HTTPS após configuração do firewall..."
if nc -zv google.com 443 &>/dev/null; then
    log_info "✅ Conexão externa via HTTPS (google.com:443) OK."
else
    log_info "⚠️ **AVISO**: Falha na conexão externa via HTTPS. Verifique as regras de saída do firewall e a conectividade geral com a internet."
fi

log_info "🧼 Limpando logs de firewall antigos (com mais de 15 dias) em /var/log/..."
log_cmd "find /var/log -name \"proxmox-firewall-*.log\" -mtime +15 -exec rm {} \\;"
log_info "✅ Limpeza de logs antigos concluída."

# Cálculo do tempo total de execução
END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))

log_info "✅ **FINALIZADO**: Configuração do firewall no nó **$NODE_NAME** concluída em $(date)."
log_info "⏳ Tempo total de execução do script: **$ELAPSED_TIME segundos**."
log_info "📋 O log detalhado de todas as operações está disponível em: **$LOG_FILE**."

log_info "---------------------------------------------------------"
log_info "📝 **RESUMO DA CONFIGURAÇÃO DO FIREWALL**"
log_info "---------------------------------------------------------"
log_info "✔️ Firewall Proxmox VE ativo com regras para:"
log_info "    - Acesso ao WebUI (porta 8006) das redes internas (via IPSet 'local_networks')"
log_info "    - Acesso SSH (porta 22) das redes internas (via IPSet 'local_networks')"
log_info "    - Comunicação interna do cluster (Corosync: 5404-5405, pve-cluster: 2224) na rede '$CLUSTER_NETWORK'"
log_info "    - Ping (ICMP) entre os nós do cluster"
log_info "    - Acesso de saída para NTP e Internet (HTTPS)"
log_info "    - Redes Locais ('local_networks' IPSet) configuradas para: $(IFS=', '; echo "${LOCAL_NETWORKS[*]}")"
log_info "---------------------------------------------------------"
log_info "🔍 **PRÓXIMOS PASSOS IMPORTANTES**:"
log_info "1.  **VERIFIQUE A CONECTIVIDADE**: Teste o acesso ao WebUI e SSH das suas redes locais."
log_info "2.  **TESTE A COMUNICAÇÃO DO CLUSTER**: Certifique-se de que os nós do cluster podem se comunicar (Corosync, pve-cluster)."
log_info "3.  **AJUSTES**: Se necessário, ajuste as regras de firewall manualmente via WebUI ou editando os arquivos `/etc/pve/firewall/cluster.fw` e `/etc/pve/nodes/$NODE_NAME/firewall/host.fw`."
log_info "---------------------------------------------------------"
