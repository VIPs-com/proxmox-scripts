#!/usr/bin/env bash

# 🚀 Script Pós-Instalação Proxmox VE 8 - Cluster Aurora/Luna (V.1.1.5 - Foco no Essencial e Usabilidade)
# Este script DEVE SER EXECUTADO INDIVIDUALMENTE em cada nó do cluster Proxmox.

# ✅ Verifique ANTES de executar:
# 1. Você já criou o cluster via WebUI? (Datacenter > Cluster > Create)
# 2. Todos os nós estão acessíveis via ping?
# 3. Tem backup dos dados importantes?

#
#
# ✅ Instruções de uso local (alternativa ao método com 'curl'):
#
#    1. Transfira este script para o seu nó Proxmox (via WebUI Shell, pendrive, scp, etc.).
#       Exemplo via SCP (executado do seu computador local):
#       scp /caminho/do/seu/script/post-install.sh root@IP_DO_PROXMOX:/root/post-install.sh
#
#    2. Torne o script executável no servidor Proxmox:
#       chmod +x /root/post-install.sh
#
#    3. Execute o script como usuário root (no servidor Proxmox):
#       /root/post-install.sh
#       OU
#       bash /root/post-install.sh
#
#
#
# 🔹 VLANs Utilizadas:
#    - 172.20.220.0/24 (Home Lab - Rede principal para comunicação do cluster)
#    - 172.21.221.0/24 (Rede Interna - Gerenciamento)
#    - 172.25.125.0/24 (Wi-Fi Arkadia)


# 🛠️ Configurações Essenciais - Podem ser sobrescritas por /etc/proxmox-postinstall.conf
CLUSTER_NETWORK="172.20.220.0/24" # Rede para comunicação interna do cluster (Corosync, pve-cluster)
NODE_NAME=$(hostname)             # Nome do servidor atual
TIMEZONE="America/Sao_Paulo"     # Fuso horário do sistema

# IPs e Hostnames de TODOS os nós do cluster.
# Adicione TODOS os pares "IP Hostname" dos seus nós aqui.
# Isso é crucial para a configuração correta do /etc/hosts e testes de conectividade.
# Exemplo: Se seus nós são 172.20.220.20 (aurora) e 172.20.220.21 (luna):
CLUSTER_NODES_CONFIG=("172.20.220.20 aurora" "172.20.220.21 luna")

LOG_FILE="/var/log/proxmox-postinstall-$(date +%Y%m%d)-$(hostname).log" # Arquivo de log específico por nó
LOCK_FILE="/etc/proxmox-postinstall.lock" # Garante que o script não seja executado múltiplas vezes
START_TIME=$(date +%s)            # Início do registro de tempo de execução

# --- INSTRUÇÕES DE EXECUÇÃO ---
#
# 📌 Método Recomendado: Via WebUI (para cada nó):
#    1. Acesse o Proxmox WebUI em cada host (ex: Aurora: https://172.20.220.20:8006, Luna: https://172.20.220.21:8006).
#    2. Vá até a seção "**Shell**" de cada nó.
#    3. Execute o comando: `curl -sL SEU_URL_DO_SCRIPT/post-install.sh | bash`
#       (Substitua `SEU_URL_DO_SCRIPT` pelo endereço onde você hospedou este script.
#        Ex: `https://raw.githubusercontent.com/seuusuario/seurepositorio/main/post-install.sh`)
#
# 📌 Método Alternativo: Via SSH (para cada nó):
#    1. Conecte-se via SSH a cada nó individualmente (ex: `ssh root@172.20.220.20`, depois `ssh root@172.20.220.21`).
#    2. Execute o comando: `curl -sL SEU_URL_DO_SCRIPT/post-install.sh | bash`
#       (ATENÇÃO: Se aplicar o "Hardening SSH" no final do script, o login de root por senha será desabilitado. Você precisará de chaves SSH para futuros acessos ao root.)

# --- FUNÇÕES AUXILIARES ---

# Funções de Log
log_info() { echo -e "\nℹ️ $*" | tee -a "$LOG_FILE"; }
log_ok() { echo -e "\n✅ $*" | tee -a "$LOG_FILE"; } # Adicionado para mensagens de sucesso
log_erro() { echo -e "\n❌ **ERRO**: $*" | tee -a "$LOG_FILE"; } # Adicionado para mensagens de erro (não críticas para abortar)

log_cmd() {
    echo -e "\n🔹 Executando Comando: $*" | tee -a "<span class="math-inline">LOG\_FILE"
eval "</span>@" >> "<span class="math-inline">LOG\_FILE" 2\>&1
local status\=</span>?
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
        local backup_dir="/var/backups/proxmox-postinstall"
        mkdir -p "<span class="math-inline">backup\_dir"
local timestamp\=</span>(date +%Y%m%d%H%M%S)
        local backup_path="<span class="math-inline">backup\_dir/</span>(basename "<span class="math-inline">file"\)\.</span>{timestamp}"
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

# Função para validar IP
validate_ip() {
    local ip="$1"
    if ! [[ "<span class="math-inline">ip" \=\~ ^\[0\-9\]\{1,3\}\\\.\[0\-9\]\{1,3\}\\\.\[0\-9\]\{1,3\}\\\.\[0\-9\]\{1,3\}</span> ]]; then
        log_erro "IP '<span class="math-inline">ip' inválido\. Use formato 'XXX\.XXX\.XXX\.XXX'\."
exit 1
fi
\}
\# Nova função\: Configura entradas em /etc/hosts para os nós do cluster
configurar\_hosts\(\) \{
log\_info "📝 Configurando entradas em /etc/hosts para os nós do cluster\.\.\."
backup\_file "/etc/hosts" \# Faz backup do /etc/hosts antes de modificar
for node\_entry in "</span>{CLUSTER_NODES_CONFIG[@]}"; do
        # Divide a string "IP HOSTNAME" em variáveis separadas
        read -r ip hostname <<< "$node_entry"

        # Verifica se o IP é válido antes de adicionar
        validate_ip "$ip"

        # Verifica se a entrada IP HOSTNAME já existe exatamente como queremos
        if ! grep -qE "^$ip\s+<span class="math-inline">hostname\(\\s\+\|</span>)" /etc/hosts; then
            # Se o IP existe mas está associado a outro hostname, remove a linha antiga
            if grep -qE "^$ip\s+" /etc/hosts; then
                log_info "Removendo entrada existente para IP '$ip' em /etc/hosts antes de adicionar o hostname correto."
                log_cmd "sed -i '/^$ip\s\+/d' /etc/hosts"
            fi
            log_info "Adicionando entrada: '$ip $hostname' a /etc/hosts."
            log_cmd "echo \"$ip $hostname\" >> /etc/hosts"
        else
            log_info "Entrada '$ip $hostname' já existe em /etc/hosts. Pulando."
        fi
    done
    log_ok "✅ Configuração de /etc/hosts concluída."
}


# Função para exibir ajuda
show_help() {
    echo "Uso: <span class="math-inline">0 \[OPÇÃO\]"
echo "Script para pós\-instalação e configuração inicial de um nó Proxmox VE 8\."
echo ""
echo "Opções\:"
echo "  \-h, \-\-help    Mostra esta mensagem de ajuda e sai\."
echo "  \-\-skip\-lock   Ignora a verificação de arquivo de lock, permitindo múltiplas execuções \(NÃO RECOMENDADO\)\."
echo ""
echo "Variáveis de configuração podem ser definidas em /etc/proxmox\-postinstall\.conf"
echo "Se este arquivo não existir, o script tentará baixá\-lo de um repositório GitHub\."
echo "Exemplo\: CLUSTER\_NETWORK\=\\"192\.168\.1\.0/24\\""
echo "         CLUSTER\_NODES\_CONFIG\=\(\\"192\.168\.1\.10 node1\\" \\"192\.168\.1\.11 node2\\"\)" \# Atualizado
echo "         TIMEZONE\=\\"America/New\_York\\""
exit 0
\}
\# \-\-\- PROCESSAMENTO DE OPÇÕES E CARREGAMENTO DE CONFIGURAÇÃO EXTERNA \-\-\-
\# Processa opções de linha de comando
SKIP\_LOCK\=false
for arg in "</span>@"; do
    case "$arg" in
        -h|--help) show_help ;;
        --skip-lock) SKIP_LOCK=true ;;
        *) log_erro "Opção inválida: $arg. Use -h ou --help para ver as opções."; exit 1 ;;
    esac
done

# --- DOWNLOAD E CARREGAMENTO DE CONFIGURAÇÃO EXTERNA ---
CONFIG_URL="https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/etc/proxmox-postinstall.conf"
CONFIG_FILE="/etc/proxmox-postinstall.conf"

# Se o arquivo de configuração local não existir, baixa do GitHub
if [[ ! -f "$CONFIG_FILE" ]]; then
    log_info "⚙️ Arquivo de configuração não encontrado localmente. Tentando baixar do GitHub: $CONFIG_URL..."
    # Usa curl diretamente e captura o status, sem log_cmd para não abortar o script em caso de falha no download
    curl -s -o "$CONFIG_FILE" "$CONFIG_URL"
    if [ $? -eq 0 ] && [ -f "$CONFIG_FILE" ]; then
        log_ok "✅ Configuração baixada e salva em $CONFIG_FILE."
    else
        log_erro "Falha ao baixar configurações do GitHub! Verifique a URL ou conectividade. Continuando com configurações padrão do script."
        # Remove qualquer arquivo parcialmente baixado para evitar carregar conteúdo incompleto
        rm -f "$CONFIG_FILE"
    fi
fi

# Carrega configurações do arquivo (local ou recém-baixado)
if [[ -f "$CONFIG_FILE" ]]; then
    log_info "⚙️ Carregando configurações de $CONFIG_FILE..."
    # Garante que as variáveis sejam carregadas para o shell atual
    source "$CONFIG_FILE"
    log_ok "✅ Configurações carregadas com sucesso!"
else
    log_info "ℹ️ Arquivo de configuração $CONFIG_FILE não encontrado. Usando configurações padrão do script."
fi

# --- INÍCIO DA EXECUÇÃO DO SCRIPT ---

# 🔒 Prevenção de Múltiplas Execuções
if [ "$SKIP_LOCK" = false ] && [ -f "$LOCK_FILE" ]; then
    log_erro "O script já foi executado anteriormente neste nó ($NODE_NAME). Abortando para evitar configurações duplicadas."
    log_info "Se você realmente precisa re-executar, remova '$LOCK_FILE' ou use '--skip-lock' (NÃO RECOMENDADO)."
    exit 1
fi
touch "$LOCK_FILE" # Cria o arquivo de lock

log_info "📅 **INÍCIO**: Execução do script de pós-instalação no nó **$NODE_NAME** em $(date)"

# --- Fase 1: Verificações Iniciais e Validação de Entrada ---

log_info "🔍 Verificando dependências essenciais do sistema (curl, ping, nc)..."
check_dependency() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_erro "O comando '$cmd' não foi encontrado. Por favor, instale-o (ex: apt install -y $cmd) e re-execute o script."
        exit 1
    fi
    log_info "✅ Dependência '<span class="math-inline">cmd' verificada\."
\}
check\_dependency "curl"
check\_dependency "ping"
check\_dependency "nc" \# Netcat, usado para os testes de porta \(apt install \-y netcat\-traditional ou netcat\-openbsd\)
\# Chama a nova função para configurar o /etc/hosts
configurar\_hosts
log\_info "🔍 Validando formato dos IPs e máscara de rede\.\.\."
\# Validar cada IP dos nós do cluster
for node\_entry in "</span>{CLUSTER_NODES_CONFIG[@]}"; do
    read -r ip hostname <<< "$node_entry"
    validate_ip "$ip"
done
log_info "✅ Formato dos IPs em CLUSTER_NODES_CONFIG verificado."

# Validar formato da rede (ex: 172.20.220.0/24)
if ! [[ "<span class="math-inline">CLUSTER\_NETWORK" \=\~ ^\[0\-9\]\{1,3\}\\\.\[0\-9\]\{1,3\}\\\.\[0\-9\]\{1,3\}\\\.\[0\-9\]\{1,3\}/\[0\-9\]\{1,2\}</span> ]]; then
    log_erro "Formato de rede inválido em CLUSTER_NETWORK. Use 'IP/MASK' (ex: 172.20.220.0/24)."
    exit 1
fi
log_info "✅ Formato de CLUSTER_NETWORK verificado."

log_info "🔍 Verificando conectividade de rede com os repositórios Debian..."
ping -c 4 ftp.debian.org &>/dev/null
if [ <span class="math-inline">? \-ne 0 \]; then
log\_info "⚠️ \*\*AVISO\*\*\: Não foi possível pingar 'ftp\.debian\.org'\. A conectividade com a internet pode estar comprometida\. As atualizações e instalações podem falhar\."
else
log\_info "✅ Conectividade com repositórios Debian OK\."
fi
log\_info "🔍 Verificando a versão do Proxmox VE\.\.\."
PVE\_VERSION\=</span>(pveversion | grep -oP 'pve-manager/\K\d+\.\d+') # Extrai "8.x"
REQUIRED_MAJOR_VERSION=8

if (( $(echo "$PVE_VERSION" | cut -d'.' -f1) < $REQUIRED_MAJOR_VERSION )); then
    log_erro "Este script requer Proxmox VE versão $REQUIRED_MAJOR_VERSION.x ou superior. Versão atual detectada: $PVE_VERSION. Não é compatível."
    exit 1
elif (( $(echo "$PVE_VERSION" | cut -d'.' -f1) > $REQUIRED_MAJOR_VERSION )); then
    log_info "⚠️ **AVISO**: Este script foi testado para Proxmox VE $REQUIRED_MAJOR_VERSION.x. Versão <span class="math-inline">PVE\_VERSION pode requerer ajustes ou não ser totalmente compatível\."
read \-p "Continuar mesmo assim? \[s/N\] " \-n 1 \-r \-t 10
echo \# Nova linha após a resposta do usuário
REPLY\=</span>{REPLY:-N}
    [[ ! <span class="math-inline">REPLY \=\~ ^\[Ss\]</span> ]] && { log_info "Script abortado pelo usuário."; exit 0; }
else
    log_info "✅ Versão do Proxmox VE (<span class="math-inline">PVE\_VERSION\) compatível\."
fi
log\_info "🔍 Verificando recursos de hardware básicos\.\.\."
MIN\_RAM\_GB\=4 \# Mínimo recomendado de RAM em GB para um nó Proxmox VE
RAM\_AVAILABLE\_GB\=</span>(free -g | awk '/Mem:/ {print $2}')
if (( RAM_AVAILABLE_GB < MIN_RAM_GB )); then
    log_info "⚠️ **AVISO**: Pouca RAM detectada ($RAM_AVAILABLE_GB GB). Mínimo recomendado para Proxmox VE é $MIN_RAM_GB GB. O desempenho pode ser afetado."
else
    log_info "✅ RAM disponível ($RAM_AVAILABLE_GB GB) OK."
fi
# Adicione mais checks aqui (CPU, disco, etc.) se desejar

# --- Fase 2: Configuração de Tempo e NTP ---

log_info "⏰ Configurando fuso horário para **$TIMEZONE** e sincronização NTP..."

# Adicionado: Verificação de conectividade NTP inicial
log_info "🔍 Verificando conectividade com servidores NTP externos (pool.ntp.org:123/UDP)..."
if ! nc -zvu pool.ntp.org 123 &>/dev/null; then
    log_erro "Falha na conexão com pool.ntp.org na porta 123 (UDP). Verifique conectividade externa e regras de firewall para NTP."
else
    log_ok "✅ Conectividade NTP externa OK."
fi

log_cmd "timedatectl set-timezone $TIMEZONE"
log_cmd "timedatectl set-ntp true" # Habilita o systemd-timesyncd
log_cmd "systemctl restart systemd-timesyncd" # Garante que o serviço esteja rodando

log_info "Aguardando e verificando a sincronização NTP inicial..."
timeout 15 bash -c 'while ! timedatectl status | grep -q "System clock synchronized: yes"; do sleep 1; done'
if [ $? -ne 0 ]; then
    log_info "⚠️ **AVISO**: Falha na sincronização NTP após 15 segundos! Tentando correção alternativa com ntpdate..."
    # Garante que ntpdate esteja instalado antes de usá-lo
    command -v ntpdate &>/dev/null || log_cmd "apt install -y ntpdate"
    # Tenta sincronizar com ntpdate e registra qualquer erro, com múltiplos fallbacks
    ntpdate -s pool.ntp.org >> "$LOG_FILE" 2>&1 \
    || ntpdate -s 0.pool.ntp.org >> "$LOG_FILE" 2>&1 \
    || ntpdate -s 1.pool.ntp.org >> "<span class="math-inline">LOG\_FILE" 2\>&1 \\
\|\| log\_erro 'Falha grave ao sincronizar com ntpdate após várias tentativas\. Verifique a conectividade de rede e as configurações de NTP\.'
else
log\_info "✅ Sincronização NTP bem\-sucedida\."
fi
\# \-\-\- Fase 3\: Gerenciamento de Repositórios e Atualizações \-\-\-
log\_info "🗑️ Desabilitando repositório de subscrição e habilitando repositório PVE no\-subscription\.\.\."
\# Faça backup de arquivos de lista de apt antes de modificar
backup\_file "/etc/apt/sources\.list\.d/pve\-enterprise\.list"
backup\_file "/etc/apt/sources\.list"
backup\_file "/etc/apt/sources\.list\.d/pve\-no\-subscription\.list"
\# CORREÇÃO\: Verifica se o arquivo existe antes de tentar modificá\-lo
if \[ \-f "/etc/apt/sources\.list\.d/pve\-enterprise\.list" \]; then
log\_info "Comentando a linha do pve\-enterprise\.list para desabilitar o repositório de subscrição\."
log\_cmd "sed \-i 's/^deb/\#deb/' /etc/apt/sources\.list\.d/pve\-enterprise\.list"
else
log\_info "ℹ️ Arquivo /etc/apt/sources\.list\.d/pve\-enterprise\.list não encontrado\. Nenhuma ação necessária para desabilitar o repositório de subscrição\."
fi
\# Adiciona/sobrescreve os repositórios Debian padrão
log\_cmd "echo 'deb http\://ftp\.debian\.org/debian bookworm main contrib' \> /etc/apt/sources\.list"
log\_cmd "echo 'deb http\://ftp\.debian\.org/debian bookworm\-updates main contrib' \>\> /etc/apt/sources\.list"
log\_cmd "echo 'deb http\://security\.debian\.org/debian\-security bookworm\-security main contrib' \>\> /etc/apt/sources\.list"
\# Adiciona o repositório Proxmox VE "no\-subscription"
log\_cmd "echo 'deb http\://download\.proxmox\.com/debian/pve bookworm pve\-no\-subscription' \> /etc/apt/sources\.list\.d/pve\-no\-subscription\.list"
log\_info "🔄 Atualizando listas de pacotes e o sistema operacional\.\.\."
log\_cmd "apt update"
log\_cmd "apt dist\-upgrade \-y"   \# Atualiza todos os pacotes e resolve dependências
log\_cmd "apt autoremove \-y"     \# Remove pacotes órfãos
log\_cmd "apt clean"             \# Limpa o cache de pacotes
log\_info "🧹 Removendo o aviso de assinatura Proxmox VE do WebUI \(se não possuir uma licença ativa\)\.\.\."
\# Cria um hook para APT que modifica o arquivo JS do WebUI
log\_cmd "echo \\"DPkg\:\:Post\-Invoke \{ \\\\\\"dpkg \-V proxmox\-widget\-toolkit \| grep \-q '/proxmoxlib\.js</span>'; if [ \\\$? -eq 1 ]; then sed -i '/.*data.status.*{/{s/\\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; fi\\\"; };\" > /etc/apt/apt.conf.d/no-nag-script"
# Reinstala o pacote para aplicar a modificação imediatamente (ou após futuras atualizações do pacote)
log_cmd "apt --reinstall install -y proxmox-widget-toolkit"
log_info "✅ Aviso de assinatura removido do WebUI (se aplicável).."

# --- Fase 4: Configuração de Firewall ---

log_info "🔍 Verificando portas críticas em uso antes de configurar o firewall..."
# Lista de portas essenciais para Proxmox e cluster
CRITICAL_PORTS="8006 22 5404 5405 2224"
for port in $CRITICAL_PORTS; do
    if ss -tuln | grep -q ":$port "; then
        log_info "⚠️ **AVISO**: Porta TCP/UDP **$port** já está em uso! Verifique se isso não conflitará com as regras do firewall Proxmox. Se estiver em uso pelo Proxmox ou Corosync, isso é normal."
    fi
done
log_info "✅ Verificação de portas concluída."

log_info "🛡️ Configurando o firewall do Proxmox VE com regras específicas..."
# REMOVIDO: log_cmd "pve-firewall stop" # ESTA LINHA FOI REMOVIDA DEFINITIVAMENTE!

# Regras para permitir acesso ao WebUI (porta 8006) e SSH (porta 22) apenas das redes locais
log_info "Permitindo acesso ao WebUI (8006) e SSH (22) apenas das redes locais..."
log_cmd "pve-firewall rule --add 172.20.220.0/24 --proto tcp --dport 8006 --accept --comment 'Acesso WebUI Home Lab'"
log_cmd "pve-firewall rule --add 172.21.221.0/24 --proto tcp --dport 8006 --accept --comment 'Acesso WebUI Rede Interna'"
log_cmd "pve-firewall rule --add 172.25.125.0/24 --proto tcp --dport 8006 --accept --comment 'Acesso WebUI Wi-Fi Arkadia'"
log_cmd "pve-firewall rule --add 172.20.220.0/24 --proto tcp --dport 22 --accept --comment 'Acesso SSH Home Lab'"
log_cmd "pve-firewall rule --add 172.21.221.0/24 --proto tcp --dport 22 --accept --comment 'Acesso SSH Rede Interna'"
log_cmd "pve-firewall rule --add 172.25.125.0/24 --proto tcp --dport 22 --accept --comment 'Acesso SSH Wi-Fi Arkadia'"

# Definindo redes locais para serem consideradas seguras pelo firewall (útil para VMs com 'firewall=1')
log_info "Configurando 'localnet' para as VLANs internas..."
log_cmd "pve-firewall localnet --add 172.20.220.0/24 --comment 'Home Lab VLAN (comunicação cluster)'"
log_cmd "pve-firewall localnet --add 172.21.221.0/24 --comment 'Rede Interna Gerenciamento'"
log_cmd "pve-firewall localnet --add 172.25.125.0/24 --comment 'Wi-Fi Arkadia'"

# CRÍTICO**: Regras para comunicação INTERNA DO CLUSTER (Corosync e pve-cluster)
# Essas regras são ABSOLUTAMENTE ESSENCIAIS para que os nós do cluster se comuniquem e funcionem corretamente.
log_info "Permitindo tráfego essencial para comunicação do cluster (Corosync, pve-cluster) na rede **$CLUSTER_NETWORK**..."
log_cmd "pve-firewall rule --add $CLUSTER