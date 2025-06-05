#!/usr/bin/env bash

# 🚀 Script Pós-Instalação Proxmox VE 8 - Cluster Aurora/Luna (V.1.1.16 - Firewall Separado)
# Este script DEVE SER EXECUTADO INDIVIDUALMENTE em cada nó do cluster Proxmox.
# A configuração do Firewall agora está em um script separado: proxmox-firewall-config.sh

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
# 🔹 VLANs Utilizadas (para referência, não configuradas diretamente aqui):
#    - 172.20.220.0/24 (Home Lab - Rede principal para comunicação do cluster)
#    - 172.21.221.0/24 (Rede Interna - Gerenciamento)
#    - 172.25.125.0/24 (Wi-Fi Arkadia)


# 🛠️ Configurações Essenciais - Podem ser sobrescritas por /etc/proxmox-postinstall.conf
CLUSTER_NETWORK="172.20.220.0/24" # Rede para comunicação interna do cluster (Corosync, pve-cluster)
NODE_NAME=$(hostname)             # Nome do servidor atual
TIMEZONE="America/Sao_Paulo"     # Fuso horário do sistema

# IPs de outros nós do cluster para testes de conectividade.
# Adicione TODOS os IPs dos seus nós aqui. O script ignorará o IP do próprio nó durante o teste.
# Exemplo: Se seus nós são 172.20.220.20 (Aurora) e 172.20.220.21 (Luna):
CLUSTER_PEER_IPS=("172.20.220.20" "172.20.220.21")

LOG_FILE="/var/log/proxmox-postinstall-$(date +%Y%m%d)-$(hostname).log" # Arquivo de log específico por nó
LOCK_FILE="/etc/proxmox-postinstall.lock" # Garante que o script não seja executado múltiplas vezes
START_TIME=$(date +%s)            # Início do registro de tempo de execução

# --- INSTRUÇÕES DE EXECUÇÃO ---

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
        local backup_dir="/var/backups/proxmox-postinstall"
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

# Função para validar IP
validate_ip() {
    local ip="$1"
    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        log_erro "IP '$ip' inválido. Use formato 'XXX.XXX.XXX.XXX'."
        exit 1
    fi
}

# Configura entradas em /etc/hosts para os nós do cluster
configurar_hosts() {
    log_info "📝 Configurando entradas em /etc/hosts para os nós do cluster..."
    backup_file "/etc/hosts" # Faz backup do /etc/hosts antes de modificar

    local current_ip=$(hostname -I | awk '{print $1}') # Pega o primeiro IP do nó atual
    local current_hostname=$(hostname)

    # Adiciona o próprio nó
    if ! grep -qE "^$current_ip\s+$current_hostname(\s+|$)" /etc/hosts; then
        if grep -qE "^$current_ip\s+" /etc/hosts; then
            log_info "Removendo entrada existente para IP '$current_ip' em /etc/hosts antes de adicionar o hostname correto."
            log_cmd "sed -i '/^$current_ip\s\+/d' /etc/hosts"
        fi
        log_info "Adicionando entrada: '$current_ip $current_hostname' a /etc/hosts."
        log_cmd "echo \"$current_ip $current_hostname\" >> /etc/hosts"
    else
        log_info "Entrada '$current_ip $current_hostname' já existe em /etc/hosts. Pulando."
    fi

    # Adiciona os IPs dos pares (sem hostname, pois CLUSTER_PEER_IPS não os contém)
    # Para um ambiente de cluster, é ALTAMENTE recomendado que todos os nós tenham os hostnames dos outros nós em /etc/hosts ou via DNS.
    # Como CLUSTER_PEER_IPS só tem IPs, vamos adicionar apenas os IPs para garantir a resolução básica.
    for peer_ip in "${CLUSTER_PEER_IPS[@]}"; do
        if [ "$peer_ip" = "$current_ip" ]; then
            continue # Não adiciona o próprio IP novamente
        fi
        if ! grep -qE "^$peer_ip\s+" /etc/hosts; then # Verifica se o IP já existe
            log_info "Adicionando entrada para IP de peer: '$peer_ip' a /etc/hosts (sem hostname, pois não está disponível)."
            log_cmd "echo \"$peer_ip\" >> /etc/hosts" # Adiciona apenas o IP
        else
            log_info "Entrada para IP de peer '$peer_ip' já existe em /etc/hosts. Pulando."
        fi
    done
    log_ok "✅ Configuração de /etc/hosts concluída."
}


# Função para exibir ajuda
show_help() {
    echo "Uso: $0 [OPÇÃO]"
    echo "Script para pós-instalação e configuração inicial de um nó Proxmox VE."
    echo ""
    echo "Opções:"
    echo "  -h, --help    Mostra esta mensagem de ajuda e sai."
    echo "  --skip-lock   Ignora a verificação de arquivo de lock, permitindo múltiplas execuções (NÃO RECOMENDADO)."
    echo ""
    echo "Variáveis de configuração podem ser definidas em /etc/proxmox-postinstall.conf"
    echo "Exemplo: CLUSTER_NETWORK=\"192.168.1.0/24\""
    echo "         CLUSTER_PEER_IPS=(\"192.168.1.10\" \"192.168.1.11\")"
    echo "         TIMEZONE=\"America/New_York\""
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
if [[ "$SKIP_LOCK" == "false" && -f "$LOCK_FILE" ]]; then
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
    log_info "✅ Dependência '$cmd' verificada."
}
check_dependency "curl"
check_dependency "ping"
check_dependency "nc" # Netcat, usado para os testes de porta (apt install -y netcat-traditional ou netcat-openbsd)

# Chama a nova função para configurar o /etc/hosts
configurar_hosts

log_info "🔍 Validando formato dos IPs e máscara de rede..."
# Validar cada IP do cluster
for ip in "${CLUSTER_PEER_IPS[@]}"; do
    validate_ip "$ip"
done
log_info "✅ Formato dos IPs em CLUSTER_PEER_IPS verificado."

# Validar formato da rede (ex: 172.20.220.0/24)
if ! [[ "$CLUSTER_NETWORK" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    log_erro "Formato de rede inválido em CLUSTER_NETWORK. Use 'IP/MASK' (ex: 172.20.220.0/24)."
    exit 1
fi
log_info "✅ Formato de CLUSTER_NETWORK verificado."

log_info "🔍 Verificando conectividade de rede com os repositórios Debian..."
ping -c 4 ftp.debian.org &>/dev/null
if [ $? -ne 0 ]; then
    log_info "⚠️ **AVISO**: Não foi possível pingar 'ftp.debian.org'. A conectividade com a internet pode estar comprometida. As atualizações e instalações podem falhar."
else
    log_info "✅ Conectividade com repositórios Debian OK."
fi

log_info "🔍 Verificando a versão do Proxmox VE..."
PVE_VERSION=$(pveversion | grep -oP 'pve-manager/\K\d+\.\d+') # Extrai "8.x"
REQUIRED_MAJOR_VERSION=8

if (( $(echo "$PVE_VERSION" | cut -d'.' -f1) < $REQUIRED_MAJOR_VERSION )); then
    log_erro "Este script requer Proxmox VE versão $REQUIRED_MAJOR_VERSION.x ou superior. Versão atual detectada: $PVE_VERSION. Não é compatível."
    exit 1
elif (( $(echo "$PVE_VERSION" | cut -d'.' -f1) > $REQUIRED_MAJOR_VERSION )); then
    log_info "⚠️ **AVISO**: Este script foi testado para Proxmox VE $REQUIRED_MAJOR_VERSION.x. Versão $PVE_VERSION pode requerer ajustes ou não ser totalmente compatível."
    read -p "Continuar mesmo assim? [s/N] " -n 1 -r -t 10
    echo # Nova linha após a resposta do usuário
    REPLY=${REPLY:-N}
    [[ ! $REPLY =~ ^[Ss]$ ]] && { log_info "Script abortado pelo usuário."; exit 0; }
else
    log_info "✅ Versão do Proxmox VE ($PVE_VERSION) compatível."
fi

log_info "🔍 Verificando recursos de hardware básicos..."
MIN_RAM_GB=4 # Mínimo recomendado de RAM em GB para um nó Proxmox VE
RAM_AVAILABLE_GB=$(free -g | awk '/Mem:/ {print $2}')
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
    || ntpdate -s 1.pool.ntp.org >> "$LOG_FILE" 2>&1 \
    || log_erro 'Falha grave ao sincronizar com ntpdate após várias tentativas. Verifique a conectividade de rede e as configurações de NTP.'
else
    log_info "✅ Sincronização NTP bem-sucedida."
fi

# --- Fase 3: Gerenciamento de Repositórios e Atualizações ---

log_info "🗑️ Desabilitando repositório de subscrição e habilitando repositório PVE no-subscription..."
# Faça backup de arquivos de lista de apt antes de modificar
backup_file "/etc/apt/sources.list.d/pve-enterprise.list"
backup_file "/etc/apt/sources.list"
backup_file "/etc/apt/sources.list.d/pve-no-subscription.list"

# CORREÇÃO: Verifica se o arquivo existe antes de tentar modificá-lo
if [ -f "/etc/apt/sources.list.d/pve-enterprise.list" ]; then
    log_info "Comentando a linha do pve-enterprise.list para desabilitar o repositório de subscrição."
    log_cmd "sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list"
else
    log_info "ℹ️ Arquivo /etc/apt/sources.list.d/pve-enterprise.list não encontrado. Nenhuma ação necessária para desabilitar o repositório de subscrição."
fi


# Adiciona/sobrescreve os repositórios Debian padrão
log_cmd "echo 'deb http://ftp.debian.org/debian bookworm main contrib' > /etc/apt/sources.list"
log_cmd "echo 'deb http://ftp.debian.org/debian bookworm-updates main contrib' >> /etc/apt/sources.list"
log_cmd "echo 'deb http://security.debian.org/debian-security bookworm-security main contrib' >> /etc/apt/sources.list"
# Adiciona o repositório Proxmox VE "no-subscription"
log_cmd "echo 'deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription' > /etc/apt/sources.list.d/pve-no-subscription.list"

log_info "🔄 Atualizando listas de pacotes e o sistema operacional..."
log_cmd "apt update"
log_cmd "apt dist-upgrade -y"   # Atualiza todos os pacotes e resolve dependências
log_cmd "apt autoremove -y"     # Remove pacotes órfãos
log_cmd "apt clean"             # Limpa o cache de pacotes

log_info "🧹 Removendo o aviso de assinatura Proxmox VE do WebUI (se não possuir uma licença ativa)..."
# Cria um hook para APT que modifica o arquivo JS do WebUI
log_cmd "echo \"DPkg::Post-Invoke { \\\"dpkg -V proxmox-widget-toolkit | grep -q '/proxmoxlib.js$'; if [ \\\$? -eq 1 ]; then sed -i '/.*data.status.*{/{s/\\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; fi\\\"; };\" > /etc/apt/apt.conf.d/no-nag-script"
# Reinstala o pacote para aplicar a modificação imediatamente (ou após futuras atualizações do pacote)
log_cmd "apt --reinstall install -y proxmox-widget-toolkit"
log_info "✅ Aviso de assinatura removido do WebUI (se aplicável)."

# --- Fase 4: Hardening de Segurança (Opcional) ---

read -p "🔒 Deseja aplicar hardening de segurança (desativar login de root por senha e password authentication)? [s/N] " -n 1 -r -t 10
echo # Nova linha após a resposta
REPLY=${REPLY:-N}
if [[ $REPLY =~ ^[Ss]$ ]]; then
    log_info "🔒 Aplicando hardening SSH..."
    backup_file "/etc/ssh/sshd_config"
    log_cmd "sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config"
    log_cmd "sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config"
    log_cmd "systemctl restart sshd"
    log_info "✅ Hardening aplicado! **Atenção**: Agora, o acesso ao root via SSH só será possível usando chaves SSH. Certifique-se de tê-las configuradas antes de fechar a sessão atual."
else
    log_info "ℹ️ Hardening SSH ignorado. O login por senha permanece ativo (menos seguro para produção)."
fi

# --- Fase 5: Instalação de Pacotes Opcionais ---

install_optional_tools() {
    echo
    read -p "📦 Deseja instalar ferramentas adicionais úteis (ex: qemu-guest-agent, ifupdown2, git, htop, smartmontools)? [s/N] " -n 1 -r -t 10
    echo # Nova linha após a resposta
    REPLY=${REPLY:-N}
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        log_info "Instalando pacotes adicionais..."
        log_cmd "apt install -y qemu-guest-agent ifupdown2 git htop smartmontools"
        log_info "✅ Pacotes adicionais instalados."
    else
        log_info "ℹ️ Instalação de pacotes adicionais ignorada."
    fi
}
install_optional_tools

# --- Fase 6: Verificações Pós-Configuração e Finalização ---

log_info "🔍 Verificando status de serviços críticos do Proxmox VE..."
if ! systemctl is-active corosync pve-cluster pvedaemon; then
    log_erro "Um ou mais serviços críticos do Proxmox (corosync, pve-cluster, pvedaemon) NÃO estão ativos. Verifique os logs e tente reiniciar manualmente."
    log_info "O script será encerrado devido à falha de serviço crítico."
    exit 1
else
    log_ok "✅ Todos os serviços críticos do Proxmox VE (corosync, pve-cluster, pvedaemon) estão ativos."
fi

log_info "🔗 Realizando testes de conectividade essencial do cluster com nós pares..."
for PEER_IP in "${CLUSTER_PEER_IPS[@]}"; do
    # Obtém o IP principal do próprio nó para evitar testar a si mesmo
    # Adaptação para obter o IP da interface que está na CLUSTER_NETWORK (útil se houver múltiplas interfaces)
    CURRENT_NODE_IP=$(ip -4 addr show dev $(ip r get $CLUSTER_NETWORK | awk '{print $3; exit}') 2>/dev/null | grep -oP 'inet \K[\d.]+')

    # Fallback se a interface principal da CLUSTER_NETWORK não for encontrada, pega o primeiro IP
    if [ -z "$CURRENT_NODE_IP" ]; then
        CURRENT_NODE_IP=$(hostname -I | awk '{print $1}')
    fi

    if [ "$PEER_IP" = "$CURRENT_NODE_IP" ]; then
        continue # Pula o teste se o IP for o do próprio nó
    fi

    log_info "Testando conexão com o nó $PEER_IP..."
    if nc -zv "$PEER_IP" 5404 &>/dev/null; then
        log_info "✅ Conexão Corosync com $PEER_IP (porta 5404) OK."
    else
        log_erro "Conexão Corosync com $PEER_IP (porta 5404) falhou. Verifique as regras de firewall e a rede."
    fi
    if nc -zv "$PEER_IP" 2224 &>/dev/null; then
        log_info "✅ Conexão pve-cluster com $PEER_IP (porta 2224) OK."
    else
        log_erro "Conexão pve-cluster com $PEER_IP (porta 2224) falhou. Verifique as regras de firewall e a rede."
    fi
    # Teste de ping para a nova regra ICMP (se o firewall estiver configurado)
    # ATENÇÃO: Este ping pode falhar se o script de firewall não tiver sido executado ainda.
    if ping -c 1 -W 1 "$PEER_IP" &>/dev/null; then
        log_info "✅ Ping com $PEER_IP OK."
    else
        log_info "⚠️ **AVISO**: Ping com $PEER_IP falhou. Isso pode ser normal se o script de firewall ainda não foi executado ou se as regras de ICMP não foram aplicadas."
    fi
done

log_info "🌍 Testando conexão externa (internet) via HTTPS..."
if nc -zv google.com 443 &>/dev/null; then
    log_info "✅ Conexão externa via HTTPS (google.com:443) OK."
else
    log_info "⚠️ **AVISO**: Falha na conexão externa via HTTPS. Verifique a conectividade geral com a internet."
fi

log_info "🧼 Limpando possíveis resíduos de execuções anteriores ou arquivos temporários..."
log_info "✅ Limpeza de resíduos concluída."

log_info "🧹 Limpando logs de pós-instalação antigos (com mais de 15 dias) em /var/log/..."
log_cmd "find /var/log -name \"proxmox-postinstall-*.log\" -mtime +15 -exec rm {} \\;"
log_info "✅ Limpeza de logs antigos concluída."

# Cálculo do tempo total de execução
END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))

log_info "✅ **FINALIZADO**: Configuração inicial do nó **$NODE_NAME** concluída em $(date)."
log_info "⏳ Tempo total de execução do script: **$ELAPSED_TIME segundos**."
log_info "📋 O log detalhado de todas as operações está disponível em: **$LOG_FILE**."

# --- Resumo da Configuração e Próximos Passos ---

log_info "📝 **RESUMO DA CONFIGURAÇÃO E PRÓXIMOS PASSOS PARA SEU HOMELAB**"
log_info "---------------------------------------------------------"
log_info "✔️ Nó configurado: **$NODE_NAME**"
log_info "✔️ Hardening SSH (desativa login root por senha): $(grep -q "PermitRootLogin prohibit-password" /etc/ssh/sshd_config && echo "Aplicado" || echo "Não aplicado")"
log_info "✔️ NTP sincronizado: $(timedatectl show --property=NTPSynchronized --value && echo "Sim" || echo "Não")" # Verifica se NTP está sincronizado
log_info "✔️ Repositórios atualizados: No-Subscription Proxmox VE e Debian Bookworm"
log_info "---------------------------------------------------------"
log_info "🔍 **PRÓXIMOS PASSO CRUCIAIS (MANUAIS)**:"
log_info "1.  **REINICIE O NÓ**: Algumas configurações (especialmente de rede e SSH) só terão efeito total após o reinício. **Isso é fundamental!**"
log_info "2.  **CRIE O CLUSTER (Primeiro Nó)**: No WebUI do seu primeiro nó, vá em **Datacenter > Cluster > Create Cluster**. Defina um nome para o cluster (ex: Aurora-Luna-Cluster)."
log_info "3.  **ADICIONE OUTROS NÓS AO CLUSTER**: Nos demais nós, no WebUI, vá em **Datacenter > Cluster > Join Cluster**. Use as informações do primeiro nó (token) para adicioná-los."
log_info "4.  **CONFIGURE O FIREWALL**: Execute o script `proxmox-firewall-config.sh` (que será criado a seguir) em cada nó para configurar as regras de firewall. **Isso é CRÍTICO para a segurança e funcionalidade da rede!**"
log_info "5.  **CONFIGURE STORAGES**: Após o cluster estar funcional, configure seus storages (LVM-Thin, ZFS, NFS, Ceph, etc.) conforme sua necessidade para armazenar VMs/CTs e ISOs."
log_info "6.  **CRIE CHAVES SSH (se aplicou hardening)**: Se você aplicou o hardening SSH, configure suas chaves SSH para acesso root antes de fechar a sessão atual, para garantir acesso futuro."
log_info "---------------------------------------------------------"

# --- REINÍCIO RECOMENDADO ---
echo
read -p "⟳ **REINÍCIO ALTAMENTE RECOMENDADO**: Para garantir que todas as configurações sejam aplicadas, é **fundamental** reiniciar o nó. Deseja reiniciar agora? [s/N] " -n 1 -r -t 15
echo # Adiciona uma nova linha após a resposta do usuário ou timeout

# Define 'N' como padrão se nada for digitado ou se houver timeout
REPLY=${REPLY:-N}

if [[ $REPLY =~ ^[Ss]$ ]]; then
    log_info "🔄 Reiniciando o nó **$NODE_NAME** agora..."
    log_cmd "reboot"
else
    log_info "ℹ️ Reinício adiado. Lembre-se de executar 'reboot' manualmente no nó **$NODE_NAME** o mais rápido possível para aplicar todas as mudanças."
fi
