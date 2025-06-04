#!/usr/bin/env bash
# proxmox-postinstall-aurora-luna.sh - Script de pós-instalação e configuração para nós Proxmox VE (Aurora e Luna)
# Autor: VIPs-com
# Versão: 1.v3.3
# Data: 2025-06-04
#
# Este script automatiza as seguintes tarefas:
# 1. Atualiza o sistema.
# 2. Remove o repositório de enterprise do Proxmox e adiciona o de no-subscription.
# 3. Desabilita a mensagem de "No valid subscription".
# 4. Instala pacotes essenciais (htop, curl, wget, net-tools, smartmontools, ifupdown2, nano, sudo).
# 5. Configura o NTP para sincronização de tempo (usando systemd-timesyncd).
# 6. Configura o firewall do Proxmox (PVE Firewall) com regras corrigidas.
# 7. **NÃO CONFIGURA HOSTNAME**: Esta etapa é manual e deve ser feita ANTES de executar este script.
# 8. **NÃO CRIA OU JUNTA CLUSTER**: Esta etapa é manual e deve ser feita ANTES de executar este script.
# 9. Configura o DNS reverso no /etc/hosts (opcional, para ambiente de lab).
# 10. Configura o teclado para ABNT2.
# 11. Instala o Cockpit (opcional).
# 12. Configura o SSH para maior segurança (desabilitando login de root por senha e autenticação por senha).
#
# Uso:
#   Execute como root: bash proxmox-postinstall-aurora-luna.sh
#   Ou: curl -sL <URL_DO_SCRIPT> | bash
#
# Variáveis de Ambiente (Opcional):
#   NODE_NAME="nome_do_no" (ex: aurora, luna)
#   CLUSTER_IP="ip_do_cluster_existente" (para juntar-se a um cluster)
#   CLUSTER_PASSWORD="senha_do_cluster"
#   CLUSTER_NAME="nome_do_cluster" (padrão: home-cluster)
#   PRIMARY_NODE_IP="ip_do_primeiro_no_do_cluster" (apenas para o segundo nó)
#   LOCAL_IP="ip_local_deste_no" (se o script não detectar corretamente)
#   CLUSTER_NETWORK="172.20.220.0/24" # Adicione a rede do seu cluster aqui para regras de firewall

# Cores para a saída do terminal
VERMELHO='\033[0;31m'
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
AZUL='\033[0;34m'
CIANO='\033[0;36m'
ROXO='\033[0;35m'
SEM_COR='\033[0m' # Reseta a cor

# Função de log
log_info() { echo -e "ℹ️  ${CIANO}$@${SEM_COR}"; }
log_success() { echo -e "✅ ${VERDE}$@${SEM_COR}"; }
log_error() { echo -e "❌ ${VERMELHO}$@${SEM_COR}"; }
log_aviso() { echo -e "⚠️  ${AMARELO}$@${SEM_COR}"; }
log_cabecalho() { echo -e "\n${ROXO}=== $1 ===${SEM_COR}"; }

# Verifica se o script está sendo executado como root
if [[ $EUID -ne 0 ]]; then
   log_error "Este script deve ser executado como root."
   exit 1
fi

log_info "Iniciando script de pós-instalação e configuração do Proxmox VE (Versão 1.v3.3)..."

# Detecta o hostname atual
CURRENT_HOSTNAME=$(hostname)
log_info "Hostname atual detectado: ${CURRENT_HOSTNAME}"

# Detecta o IP local principal
LOCAL_IP=$(hostname -I | awk '{print $1}')
if [[ -z "$LOCAL_IP" ]]; then
    log_error "Não foi possível detectar o IP local. Por favor, defina a variável de ambiente LOCAL_IP antes de executar o script."
    exit 1
fi
log_info "IP local detectado: ${LOCAL_IP}"

# Define o nome do nó com base no IP detectado, se NODE_NAME não estiver definido
if [[ -z "$NODE_NAME" ]]; then
    if [[ "$LOCAL_IP" == "172.20.220.20" ]]; then
        NODE_NAME="aurora"
    elif [[ "$LOCAL_IP" == "172.20.220.21" ]]; then
        NODE_NAME="luna"
    else
        log_aviso "IP local (${LOCAL_IP}) não corresponde a 'aurora' ou 'luna'. Usando hostname atual: ${CURRENT_HOSTNAME}."
        NODE_NAME="${CURRENT_HOSTNAME}"
    fi
fi
log_info "Nome do nó definido para: ${NODE_NAME}"

# Define o nome do cluster (padrão ou via variável de ambiente)
CLUSTER_NAME=${CLUSTER_NAME:-"home-cluster"}
log_info "Nome do cluster definido para: ${CLUSTER_NAME}"

# Define a rede do cluster para as regras de firewall (MUITO IMPORTANTE!)
# Adapte esta variável para a rede que seus nós Proxmox usam para comunicação de cluster.
# Ex: "172.20.220.0/24" se seus nós estiverem em 172.20.220.20 e 172.20.220.21
CLUSTER_NETWORK=${CLUSTER_NETWORK:-"172.20.220.0/24"}
log_info "Rede do Cluster para Firewall definida como: ${CLUSTER_NETWORK}"


# ========== 1. Atualizar o sistema ==========
log_cabecalho "1/12 - Atualizando o sistema"
log_info "Executando apt update e apt dist-upgrade..."
apt update && apt dist-upgrade -y
if [[ $? -eq 0 ]]; then
    log_success "Sistema atualizado com sucesso."
else
    log_error "Falha ao atualizar o sistema. Verifique a conectividade com os repositórios."
fi

# ========== 2. Remover repositório enterprise e adicionar no-subscription ==========
log_cabecalho "2/12 - Configurando Repositórios Proxmox"
log_info "Removendo repositório enterprise..."
if [ -f "/etc/apt/sources.list.d/pve-enterprise.list" ]; then
    sed -i "s/^deb/#deb/" /etc/apt/sources.list.d/pve-enterprise.list
    log_success "Repositório enterprise desabilitado."
else
    log_info "Arquivo '/etc/apt/sources.list.d/pve-enterprise.list' não encontrado. Nenhuma ação necessária."
fi

log_info "Adicionando repositório no-subscription..."
# Garante que o repositório no-subscription esteja apenas em seu próprio arquivo, evitando duplicação
if ! grep -q "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" /etc/apt/sources.list.d/pve-no-subscription.list; then
    echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" > /etc/apt/sources.list.d/pve-no-subscription.list
    log_success "Repositório no-subscription adicionado."
else
    log_aviso "Repositório no-subscription já existe em '/etc/apt/sources.list.d/pve-no-subscription.list'."
fi

# Remove qualquer entrada duplicada de no-subscription em /etc/apt/sources.list
if grep -q "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" /etc/apt/sources.list; then
    log_info "Removendo entrada duplicada do repositório no-subscription em '/etc/apt/sources.list'."
    sed -i '/deb http:\/\/download.proxmox.com\/debian\/pve bookworm pve-no-subscription/d' /etc/apt/sources.list
fi

apt update
if [[ $? -eq 0 ]]; then
    log_success "apt update após mudança de repositório concluído."
else
    log_error "Falha ao executar apt update após mudança de repositório. Verifique a configuração."
fi

# ========== 3. Desabilitar mensagem de "No valid subscription" ==========
log_cabecalho "3/12 - Desabilitando Mensagem de Assinatura"
log_info "Desabilitando popup de 'No valid subscription' na interface web..."
# Expressão sed corrigida para Proxmox VE 8
sed -i.bak "s/data.status !== 'active'/data.status === 'active'/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
if [[ $? -eq 0 ]]; then
    log_success "Mensagem de assinatura desabilitada. (Pode ser necessário reiniciar o serviço pveproxy ou o navegador para ver a mudança)."
else
    log_error "Falha ao desabilitar a mensagem de assinatura. Verifique o arquivo '/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js'."
fi

# ========== 4. Instalar pacotes essenciais ==========
log_cabecalho "4/12 - Instalando Pacotes Essenciais"
# Removido 'ntp' para evitar conflito com systemd-timesyncd
REQUIRED_PACKAGES="htop curl wget net-tools smartmontools ifupdown2 nano sudo"
log_info "Instalando pacotes: ${REQUIRED_PACKAGES}..."
apt install -y ${REQUIRED_PACKAGES}
if [[ $? -eq 0 ]]; then
    log_success "Pacotes essenciais instalados com sucesso."
else
    log_error "Falha ao instalar pacotes essenciais."
fi

# ========== 5. Configurar o NTP para sincronização de tempo ==========
log_cabecalho "5/12 - Configurando Sincronização de Tempo (NTP)"
log_info "Verificando e configurando NTP (usando systemd-timesyncd)..."

# Garante que systemd-timesyncd está instalado
if ! systemctl is-enabled --quiet systemd-timesyncd; then
    log_info "Instalando/habilitando systemd-timesyncd..."
    apt install -y systemd-timesyncd
    systemctl enable systemd-timesyncd
    systemctl start systemd-timesyncd
fi

# Garante que systemd-timesyncd está ativo e usando pool.ntp.org
timedatectl set-ntp true
if [[ $? -eq 0 ]]; then
    log_success "Sincronização de tempo via systemd-timesyncd ativada."
else
    log_error "Falha ao ativar sincronização de tempo via systemd-timesyncd. Verifique o status do serviço."
fi

# Reinicia o serviço para aplicar as configurações
systemctl restart systemd-timesyncd
if [[ $? -eq 0 ]]; then
    log_success "Serviço systemd-timesyncd reiniciado."
else
    log_error "Falha ao reiniciar o serviço systemd-timesyncd. Verifique 'systemctl status systemd-timesyncd'."
fi

# Opcional: Instala ntpdate como fallback para sincronização manual se necessário
if ! command -v ntpdate >/dev/null 2>&1; then
    log_info "Instalando 'ntpdate' como ferramenta de sincronização NTP de fallback..."
    apt install -y ntpdate
    if [[ $? -eq 0 ]]; then
        log_success "'ntpdate' instalado com sucesso."
    else
        log_aviso "Falha ao instalar 'ntpdate'. A sincronização manual pode não ser possível."
    fi
fi


# ========== 6. Configurar o firewall do Proxmox (PVE Firewall) ==========
log_cabecalho "6/12 - Configurando Firewall do Proxmox VE"
log_info "Reiniciando o serviço pvedaemon para garantir que o firewall possa se comunicar..."
systemctl restart pvedaemon
sleep 5 # Aguarda um pouco para o serviço iniciar

if ! systemctl is-active pvedaemon; then
    log_error "O serviço pvedaemon NÃO está ativo após o reinício. O firewall pode não funcionar corretamente. O script será encerrado."
    exit 1
else
    log_success "Serviço pvedaemon está ativo."
fi

log_info "Desativando e limpando todas as regras existentes do firewall Proxmox VE..."
pve-firewall stop # Garante que o firewall está parado
pve-firewall flush # Limpa todas as regras existentes
log_success "Firewall Proxmox VE desativado e regras limpas com sucesso."

log_info "Habilitando e iniciando PVE Firewall..."
pve-firewall start # Este comando habilita e inicia o firewall
log_success "PVE Firewall habilitado e iniciado."

log_info "Adicionando regras básicas para o cluster e rede local..."
# Regras para permitir acesso ao WebUI (porta 8006) e SSH (porta 22) apenas das redes locais
# Sintaxe corrigida: pve-firewall add <rule>
pve-firewall add host --dir in --proto tcp --dport 8006 --source 172.20.220.0/24 --action ACCEPT --comment 'Acesso WebUI Home Lab'
pve-firewall add host --dir in --proto tcp --dport 8006 --source 172.21.221.0/24 --action ACCEPT --comment 'Acesso WebUI Rede Interna'
pve-firewall add host --dir in --proto tcp --dport 8006 --source 172.25.125.0/24 --action ACCEPT --comment 'Acesso WebUI Wi-Fi Arkadia'
pve-firewall add host --dir in --proto tcp --dport 22 --source 172.20.220.0/24 --action ACCEPT --comment 'Acesso SSH Home Lab'
pve-firewall add host --dir in --proto tcp --dport 22 --source 172.21.221.0/24 --action ACCEPT --comment 'Acesso SSH Rede Interna'
pve-firewall add host --dir in --proto tcp --dport 22 --source 172.25.125.0/24 --action ACCEPT --comment 'Acesso SSH Wi-Fi Arkadia'
log_success "Regras de firewall para WebUI e SSH adicionadas."

# Correção para localnet: adicionar uma por uma
log_info "Configurando redes locais para o firewall (localnet)..."
# Sintaxe corrigida: pve-firewall localnet add <network>
pve-firewall localnet add 172.20.220.0/24 --comment 'Home Lab VLAN (comunicação cluster)'
pve-firewall localnet add 172.21.221.0/24 --comment 'Rede Interna Gerenciamento'
pve-firewall localnet add 172.25.125.0/24 --comment 'Wi-Fi Arkadia'
log_success "Regras de firewall para redes locais adicionadas."

# Regras para permitir tráfego de/para as redes locais (usando localnet)
pve-firewall add host --dir in --source localnet --action ACCEPT --comment 'Permitir entrada de localnet'
pve-firewall add host --dir out --dest localnet --action ACCEPT --comment 'Permitir saída para localnet'
log_success "Regras de firewall para tráfego localnet adicionadas."

# Regras CRÍTICAS para comunicação INTERNA DO CLUSTER (Corosync e pve-cluster)
log_info "Permitindo tráfego essencial para comunicação do cluster (Corosync, pve-cluster) na rede ${CLUSTER_NETWORK}..."
pve-firewall add host --dir in --source "${CLUSTER_NETWORK}" --proto udp --dport 5404 --action ACCEPT --comment 'Corosync UDP 5404'
pve-firewall add host --dir in --source "${CLUSTER_NETWORK}" --proto udp --dport 5405 --action ACCEPT --comment 'Corosync UDP 5405'
pve-firewall add host --dir in --source "${CLUSTER_NETWORK}" --proto tcp --dport 2224 --action ACCEPT --comment 'pve-cluster TCP 2224'
log_success "Regras de firewall para comunicação de cluster adicionadas."

# Permitir tráfego ICMP (ping) entre os nós do cluster para facilitar diagnósticos
log_info "Permitindo tráfego ICMP (ping) entre os nós do cluster..."
pve-firewall add host --dir in --source "${CLUSTER_NETWORK}" --proto icmp --action ACCEPT --comment 'Permitir ping entre nós do cluster'
log_success "Regra de firewall para ping adicionada."

# Regra para permitir tráfego de SAÍDA para NTP (servidores externos)
log_info "Permitindo tráfego de saída para servidores NTP (porta UDP 123)..."
pve-firewall add host --dir out --proto udp --dport 123 --action ACCEPT --comment 'Permitir saída para NTP'
log_success "Regra de firewall para NTP de saída adicionada."

# Regra final: Bloquear todo o tráfego não explicitamente permitido (default deny)
log_info "Aplicando regra de bloqueio padrão para todo o tráfego não autorizado..."
pve-firewall add host --dir in --source 0.0.0.0/0 --action DROP --comment 'Bloquear tráfego não autorizado por padrão'
log_success "Regra de bloqueio padrão adicionada."

log_info "Reiniciando PVE Firewall para aplicar as regras..."
pve-firewall restart
log_success "PVE Firewall configurado e reiniciado."

# ========== 7. Configurar o hostname (MANUAL) ==========
log_cabecalho "7/12 - Configurar o hostname (MANUAL)"
log_info "Esta etapa NÃO é automatizada por este script."
log_info "Certifique-se de que o hostname deste nó foi configurado manualmente ANTES de executar este script."
log_info "Você pode configurar o hostname usando o comando 'hostnamectl set-hostname <novo_hostname>' e adicionando uma entrada em /etc/hosts, se necessário."
log_info "O hostname atual detectado é: ${CURRENT_HOSTNAME}"


# ========== 8. Gerenciamento de Cluster Proxmox (MANUAL) ==========
log_cabecalho "8/12 - Gerenciamento de Cluster Proxmox (MANUAL)"
log_info "Esta etapa NÃO é automatizada por este script."
log_info "Certifique-se de que seu cluster Proxmox VE foi criado e/ou os nós foram unidos MANUALMENTE via WebUI ANTES de executar este script."
log_info "Isso garante o controle total sobre a configuração do cluster e a geração de chaves."
log_info "Verificando se este nó faz parte de um cluster..."
if pvecm status | grep -q "Cluster Name:"; then
    log_success "Este nó já faz parte de um cluster. Verifique o status do quorum."
    if pvecm status | grep -q "Quorate: Yes"; then
        log_success "Cluster está quorate (OK)."
    else
        log_error "Cluster NÃO está quorate! Verifique a comunicação entre os nós."
    fi
else
    log_aviso "Este nó AINDA NÃO faz parte de um cluster. Lembre-se de criar ou juntar o cluster manualmente via WebUI."
fi


# ========== 9. Configurar o DNS reverso em /etc/hosts (opcional) ==========
log_cabecalho "9/12 - Configurando DNS Reverso em /etc/hosts"
log_info "Adicionando entradas de DNS reverso para os IPs do cluster em /etc/hosts (se não existirem)..."
# IPs de peers do cluster Proxmox (adicione todos os nós do cluster, incluindo o próprio)
# CLUSTER_PEER_IPS=("172.20.220.20" "172.20.220.21")
# Adicionar IPs do cluster para resolução local
for ip in "${CLUSTER_PEER_IPS[@]}"; do
    if [[ "$ip" == "172.20.220.20" ]]; then
        HOSTNAME_TO_ADD="aurora.local aurora"
    elif [[ "$ip" == "172.20.220.21" ]]; then
        HOSTNAME_TO_ADD="luna.local luna"
    else
        HOSTNAME_TO_ADD="" # Não adiciona se não for um dos IPs conhecidos
    fi

    if [[ -n "$HOSTNAME_TO_ADD" ]]; then
        # Verifica se a linha já existe para evitar duplicação
        if ! grep -qE "^${ip}\s+${HOSTNAME_TO_ADD}$" /etc/hosts; then
            # Se o IP existe mas com hostname diferente, remove a linha antiga
            if grep -qE "^${ip}\s+" /etc/hosts; then
                sed -i "/^${ip}\s+/d" /etc/hosts
                log_info "Removida entrada antiga para ${ip} em /etc/hosts."
            fi
            echo "${ip} ${HOSTNAME_TO_ADD}" >> /etc/hosts
            log_success "Adicionado '${ip} ${HOSTNAME_TO_ADD}' ao /etc/hosts."
        else
            log_info "Entrada '${ip} ${HOSTNAME_TO_ADD}' já existe em /etc/hosts. Pulando."
        fi
    fi
done
log_success "/etc/hosts configurado."

# ========== 10. Configurar o teclado para ABNT2 ==========
log_cabecalho "10/12 - Configurando Teclado ABNT2"
log_info "Configurando teclado para ABNT2..."
# Este comando interativo não pode ser totalmente automatizado sem 'debconf-set-selections'
# Apenas informa o usuário para seguir as instruções
log_aviso "O comando 'dpkg-reconfigure keyboard-configuration' é interativo. Por favor, selecione as seguintes opções quando solicitado:"
log_aviso "  - Generic 105-key PC (Intl.)"
log_aviso "  - Portuguese (Brazil)"
log_aviso "  - Portuguese (Brazil, abnt2)"
log_aviso "  - The default for the keyboard layout"
log_aviso "  - No compose key"
log_aviso "  - No"
dpkg-reconfigure keyboard-configuration
log_success "Configuração de teclado ABNT2 iniciada. Siga as instruções no terminal."

# ========== 11. Instalar o Cockpit (opcional) ==========
log_cabecalho "11/12 - Instalando Cockpit (Opcional)"
log_info "Verificando e instalando Cockpit..."
if ! command -v cockpit >/dev/null 2>&1; then
    apt install -y cockpit
    if [[ $? -eq 0 ]]; then
        log_success "Cockpit instalado com sucesso. Acesse em https://${LOCAL_IP}:9090"
    else
        log_error "Falha ao instalar Cockpit."
    fi
else
    log_info "Cockpit já está instalado."
fi

# ========== 12. Configurar SSH para maior segurança ==========
log_cabecalho "12/12 - Configurando SSH para maior segurança"
log_info "Aplicando hardening SSH: Desabilitando login de root por senha e autenticação por senha..."
log_aviso "ATENÇÃO: Após esta configuração, o login de root via SSH só será possível usando CHAVES SSH."
log_aviso "Certifique-se de ter suas chaves SSH configuradas e testadas ANTES de fechar a sessão atual para evitar perder o acesso."

SSH_CONFIG_FILE="/etc/ssh/sshd_config"
# Faz backup do arquivo de configuração SSH antes de modificar
cp -p "$SSH_CONFIG_FILE" "${SSH_CONFIG_FILE}.bak_$(date +%Y%m%d%H%M%S)"
log_info "Backup de '$SSH_CONFIG_FILE' criado."

# Desabilita login de root por senha
if grep -q "^#PermitRootLogin" "$SSH_CONFIG_FILE"; then
    sed -i 's/^#PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSH_CONFIG_FILE"
elif grep -q "^PermitRootLogin" "$SSH_CONFIG_FILE"; then
    sed -i 's/^PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSH_CONFIG_FILE"
else
    echo "PermitRootLogin prohibit-password" >> "$SSH_CONFIG_FILE"
fi

# Desabilita autenticação por senha
if grep -q "^#PasswordAuthentication" "$SSH_CONFIG_FILE"; then
    sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG_FILE"
elif grep -q "^PasswordAuthentication" "$SSH_CONFIG_FILE"; then
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG_FILE"
else
    echo "PasswordAuthentication no" >> "$SSH_CONFIG_FILE"
fi

log_info "Reiniciando serviço SSH..."
systemctl restart ssh
if [[ $? -eq 0 ]]; then
    log_success "Configuração SSH aplicada e serviço reiniciado. Login de root por senha e autenticação por senha desabilitados."
else
    log_error "Falha ao reiniciar o serviço SSH. Verifique a configuração manual e os logs do SSH ('journalctl -xeu ssh')."
fi

log_cabecalho "Configuração Concluída!"
log_success "O script de pós-instalação foi concluído."
log_info "Por favor, execute o script 'verifica-rede.sh' novamente para um diagnóstico completo do ambiente."
log_info "Lembre-se de investigar o aviso do NVMe (/dev/nvme0) e considerar um UPS para evitar desligamentos não seguros."

exit 0
