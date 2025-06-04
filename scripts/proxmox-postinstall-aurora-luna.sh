#!/usr/bin/env bash
# proxmox-postinstall-aurora-luna.sh - Script de pós-instalação e configuração para nós Proxmox VE (Aurora e Luna)
# Autor: VIPs-com
# Versão: 1.v3.1
# Data: 2025-06-04
#
# Este script automatiza as seguintes tarefas:
# 1. Atualiza o sistema.
# 2. Remove o repositório de enterprise do Proxmox e adiciona o de no-subscription.
# 3. Desabilita a mensagem de "No valid subscription".
# 4. Instala pacotes essenciais (htop, curl, wget, net-tools, smartmontools, ntp, ifupdown2, nano, sudo).
# 5. Configura o NTP para sincronização de tempo.
# 6. Configura o firewall do Proxmox (PVE Firewall).
# 7. Configura o hostname (se não for "aurora" ou "luna").
# 8. Cria um cluster Proxmox (se ainda não estiver em um).
# 9. Configura o DNS reverso no /etc/hosts (opcional, para ambiente de lab).
# 10. Configura o teclado para ABNT2.
# 11. Instala o Cockpit (opcional).
# 12. Configura o SSH para permitir login de root e autenticação por senha (AVISO: Menos seguro).
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

log_info "Iniciando script de pós-instalação e configuração do Proxmox VE (Versão 1.v3.1)..."

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
sed -i "s/^deb/#deb/" /etc/apt/sources.list.d/pve-enterprise.list
log_success "Repositório enterprise desabilitado."

log_info "Adicionando repositório no-subscription..."
if ! grep -q "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" /etc/apt/sources.list; then
    echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" >> /etc/apt/sources.list
    log_success "Repositório no-subscription adicionado."
else
    log_aviso "Repositório no-subscription já existe."
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
sed -Ezi.bak "s/(Ext.Msg.show\({title: gettext\('No valid subscription'\),.*)/\1\n    void(0);/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
if [[ $? -eq 0 ]]; then
    log_success "Mensagem de assinatura desabilitada. (Pode ser necessário reiniciar o serviço pveproxy ou o navegador para ver a mudança)."
else
    log_error "Falha ao desabilitar a mensagem de assinatura."
fi

# ========== 4. Instalar pacotes essenciais ==========
log_cabecalho "4/12 - Instalando Pacotes Essenciais"
REQUIRED_PACKAGES="htop curl wget net-tools smartmontools ntp ifupdown2 nano sudo"
log_info "Instalando pacotes: ${REQUIRED_PACKAGES}..."
apt install -y ${REQUIRED_PACKAGES}
if [[ $? -eq 0 ]]; then
    log_success "Pacotes essenciais instalados com sucesso."
else
    log_error "Falha ao instalar pacotes essenciais."
fi

# ========== 5. Configurar o NTP para sincronização de tempo ==========
log_cabecalho "5/12 - Configurando Sincronização de Tempo (NTP)"
log_info "Verificando e configurando NTP..."
# Garante que systemd-timesyncd está ativo e usando pool.ntp.org
timedatectl set-ntp true
if [[ $? -eq 0 ]]; then
    log_success "Sincronização de tempo via systemd-timesyncd ativada."
else
    log_error "Falha ao ativar sincronização de tempo via systemd-timesyncd."
fi

# Verifica se o serviço ntp (se instalado) está ativo
if systemctl is-active --quiet ntp; then
    log_success "Serviço NTP (daemon) está ativo."
else
    log_aviso "Serviço NTP (daemon) não está ativo. Usando systemd-timesyncd para sincronização de tempo."
fi

# Reinicia o serviço para aplicar as configurações
systemctl restart systemd-timesyncd
log_success "Serviço systemd-timesyncd reiniciado."

# ========== 6. Configurar o firewall do Proxmox (PVE Firewall) ==========
log_cabecalho "6/12 - Configurando Firewall do Proxmox VE"
log_info "Habilitando PVE Firewall..."
pve-firewall start
pve-firewall enable
log_success "PVE Firewall habilitado e iniciado."

log_info "Adicionando regras básicas para o cluster e rede local..."
# Regras para permitir comunicação de cluster e acesso à web UI
pve-firewall allow --dir in --proto tcp --dport 8006 # Proxmox Web UI
pve-firewall allow --dir in --proto tcp --dport 22   # SSH
pve-firewall allow --dir in --proto udp --dport 5404 # Corosync (cluster)
pve-firewall allow --dir in --proto udp --dport 5405 # Corosync (cluster)

# Correção para localnet: adicionar uma por uma
# A imagem que você me mostrou tinha 172.20.220.0/24;172.21.221.0/24;172.25.125.0/24
# Vou adicionar cada uma separadamente.
log_info "Configurando redes locais para o firewall (localnet)..."
pve-firewall localnet --add 172.20.220.0/24
pve-firewall localnet --add 172.21.221.0/24
pve-firewall localnet --add 172.25.125.0/24
log_success "Regras de firewall para redes locais adicionadas."

# Regra para permitir tráfego de/para as redes locais
pve-firewall allow --dir in --source localnet
pve-firewall allow --dir out --dest localnet
log_success "Regras de firewall para tráfego localnet adicionadas."

log_info "Reiniciando PVE Firewall para aplicar as regras..."
pve-firewall restart
log_success "PVE Firewall configurado e reiniciado."

# ========== 7. Configurar o hostname (se necessário) ==========
log_cabecalho "7/12 - Configurando Hostname"
if [[ "$CURRENT_HOSTNAME" != "$NODE_NAME" ]]; then
    log_info "Configurando hostname para ${NODE_NAME}..."
    hostnamectl set-hostname "${NODE_NAME}"
    echo "${LOCAL_IP} ${NODE_NAME}.local ${NODE_NAME}" >> /etc/hosts # Adiciona ao hosts para resolução local
    log_success "Hostname configurado para ${NODE_NAME}."
    log_aviso "Pode ser necessário reiniciar o sistema para que o novo hostname seja totalmente aplicado em todos os serviços."
else
    log_info "Hostname já está configurado como ${NODE_NAME}. Nenhuma alteração necessária."
fi

# ========== 8. Criar ou juntar-se a um cluster Proxmox ==========
log_cabecalho "8/12 - Gerenciamento de Cluster Proxmox"
if ! command -v pvecm >/dev/null 2>&1; then
    log_aviso "Comando 'pvecm' não encontrado. Proxmox VE pode não estar totalmente instalado ou o pacote 'pve-cluster' está ausente."
else
    if pvecm status | grep -q "Cluster Name:"; then
        log_info "Este nó já faz parte de um cluster."
        # Verifica se o cluster está quorate
        if pvecm status | grep -q "Quorate: Yes"; then
            log_success "Cluster está quorate (OK)."
        else
            log_error "Cluster NÃO está quorate! Verifique a comunicação entre os nós."
        fi
    else
        log_info "Este nó não faz parte de um cluster."
        if [[ "$NODE_NAME" == "aurora" ]]; then
            log_info "Criando novo cluster '${CLUSTER_NAME}' no nó 'aurora'..."
            pvecm create "${CLUSTER_NAME}"
            if [[ $? -eq 0 ]]; then
                log_success "Cluster '${CLUSTER_NAME}' criado com sucesso."
            else
                log_error "Falha ao criar o cluster '${CLUSTER_NAME}'. Verifique os logs."
            fi
        elif [[ "$NODE_NAME" == "luna" ]]; then
            if [[ -z "$PRIMARY_NODE_IP" ]]; then
                log_error "Para o nó 'luna', a variável PRIMARY_NODE_IP deve ser definida para o IP do nó 'aurora' (ex: export PRIMARY_NODE_IP='172.20.220.20')."
            else
                log_info "Tentando juntar o nó 'luna' ao cluster existente em ${PRIMARY_NODE_IP}..."
                # Solicita a senha do root do nó primário se não for fornecida via CLUSTER_PASSWORD
                if [[ -z "$CLUSTER_PASSWORD" ]]; then
                    read -s -p "Digite a senha do root para o nó primário (${PRIMARY_NODE_IP}): " CLUSTER_PASSWORD
                    echo # Nova linha após a senha
                fi
                pvecm add "${PRIMARY_NODE_IP}" -force -api-args "password=${CLUSTER_PASSWORD}"
                if [[ $? -eq 0 ]]; then
                    log_success "Nó 'luna' adicionado ao cluster com sucesso."
                else
                    log_error "Falha ao adicionar o nó 'luna' ao cluster. Verifique a conectividade e a senha."
                fi
            fi
        else
            log_aviso "Nome do nó não é 'aurora' nem 'luna'. Não foi possível criar ou juntar-se a um cluster automaticamente."
        fi
    fi
fi

# ========== 9. Configurar o DNS reverso no /etc/hosts (opcional) ==========
log_cabecalho "9/12 - Configurando DNS Reverso em /etc/hosts"
log_info "Adicionando entradas de DNS reverso para os IPs do cluster em /etc/hosts (se não existirem)..."
for ip in "${CLUSTER_PEER_IPS[@]}"; do
    if [[ "$ip" == "172.20.220.20" ]]; then
        HOSTNAME_TO_ADD="aurora.local aurora"
    elif [[ "$ip" == "172.20.220.21" ]]; then
        HOSTNAME_TO_ADD="luna.local luna"
    else
        HOSTNAME_TO_ADD="" # Não adiciona se não for um dos IPs conhecidos
    fi

    if [[ -n "$HOSTNAME_TO_ADD" ]]; then
        if ! grep -q "$ip $HOSTNAME_TO_ADD" /etc/hosts; then
            echo "$ip $HOSTNAME_TO_ADD" >> /etc/hosts
            log_success "Adicionado '$ip $HOSTNAME_TO_ADD' ao /etc/hosts."
        else
            log_info "Entrada '$ip $HOSTNAME_TO_ADD' já existe em /etc/hosts."
        fi
    fi
done
log_success "/etc/hosts configurado."

# ========== 10. Configurar o teclado para ABNT2 ==========
log_cabecalho "10/12 - Configurando Teclado ABNT2"
log_info "Configurando teclado para ABNT2..."
dpkg-reconfigure keyboard-configuration
# Selecione 'Generic 105-key PC (Intl.)'
# Selecione 'Portuguese (Brazil)'
# Selecione 'Portuguese (Brazil, abnt2)'
# Selecione 'The default for the keyboard layout'
# Selecione 'No compose key'
# Selecione 'No'
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

# ========== 12. Configurar SSH para permitir login de root e autenticação por senha ==========
log_cabecalho "12/12 - Configurando SSH (AVISO: Menos Seguro)"
log_aviso "AVISO: Permitir login de root e autenticação por senha via SSH é MENOS SEGURO."
log_aviso "Recomenda-se usar autenticação por chave SSH para maior segurança em ambientes de produção."

SSH_CONFIG_FILE="/etc/ssh/sshd_config"
log_info "Configurando SSH para permitir login de root e autenticação por senha..."

# Permite login de root
if grep -q "^#PermitRootLogin" "$SSH_CONFIG_FILE"; then
    sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin yes/' "$SSH_CONFIG_FILE"
elif grep -q "^PermitRootLogin" "$SSH_CONFIG_FILE"; then
    sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' "$SSH_CONFIG_FILE"
else
    echo "PermitRootLogin yes" >> "$SSH_CONFIG_FILE"
fi

# Permite autenticação por senha
if grep -q "^#PasswordAuthentication" "$SSH_CONFIG_FILE"; then
    sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' "$SSH_CONFIG_FILE"
elif grep -q "^PasswordAuthentication" "$SSH_CONFIG_FILE"; then
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_CONFIG_FILE"
else
    echo "PasswordAuthentication yes" >> "$SSH_CONFIG_FILE"
fi

log_info "Reiniciando serviço SSH..."
systemctl restart ssh
if [[ $? -eq 0 ]]; then
    log_success "Configuração SSH aplicada e serviço reiniciado."
else
    log_error "Falha ao reiniciar o serviço SSH. Verifique a configuração manual."
fi

log_cabecalho "Configuração Concluída!"
log_success "O script de pós-instalação foi concluído."
log_info "Por favor, execute o script 'verifica-rede.sh' novamente para um diagnóstico completo do ambiente."
log_info "Lembre-se de investigar o aviso do NVMe (/dev/nvme0) e considerar um UPS para evitar desligamentos não seguros."

exit 0
