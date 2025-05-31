#!/usr/bin/env bash

# 🚀 Script Pós-Instalação Proxmox VE 8 - Cluster Aurora/Luna (Versão 10/10 - Foco no Essencial e Usabilidade)
# Este script DEVE SER EXECUTADO INDIVIDUALMENTE em cada nó do cluster Proxmox.

# ✅ Verifique ANTES de executar:
# 1. Você já criou o cluster via WebUI? (Datacenter > Cluster > Create)
# 2. Todos os nós estão acessíveis via ping?
# 3. Tem backup dos dados importantes?

###### Commit + Push ##
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
######
#
# 🔹 VLANs Utilizadas:
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
#
# 📌 **Método Recomendado: Via WebUI (para cada nó)**:
#    1. Acesse o Proxmox WebUI em cada host (ex: Aurora: https://172.20.220.20:8006, Luna: https://172.20.220.21:8006).
#    2. Vá até a seção "**Shell**" de cada nó.
#    3. Execute o comando: `curl -sL SEU_URL_DO_SCRIPT/post-install.sh | bash`
#       (Substitua `SEU_URL_DO_SCRIPT` pelo endereço onde você hospedou este script.
#        Ex: `https://raw.githubusercontent.com/seuusuario/seurepositorio/main/post-install.sh`)
#
# 📌 **Método Alternativo: Via SSH (para cada nó)**:
#    1. Conecte-se via SSH a cada nó individualmente (ex: `ssh root@172.20.220.20`, depois `ssh root@172.20.220.21`).
#    2. Execute o comando: `curl -sL SEU_URL_DO_SCRIPT/post-install.sh | bash`
#       (ATENÇÃO: Se aplicar o "Hardening SSH" no final do script, o login de root por senha será desabilitado. Você precisará de chaves SSH para futuros acessos ao root.)

# --- FUNÇÕES AUXILIARES ---

# Funções de Log
log_info() { echo -e "\nℹ️ $*" | tee -a "$LOG_FILE"; }
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
        log_info "❌ **ERRO**: IP '$ip' inválido. Use formato 'XXX.XXX.XXX.XXX'."
        exit 1
    fi
}

# Função para exibir ajuda
show_help() {
    echo "Uso: $0 [OPÇÃO]"
    echo "Script para pós-instalação e configuração inicial de um nó Proxmox VE 8."
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
        *) echo "❌ Opção inválida: $arg. Use -h ou --help para ver as opções." >&2; exit 1 ;;
    esac
done

# Carrega configurações de arquivo externo (se existir)
if [ -f "/etc/proxmox-postinstall.conf" ]; then
    log_info "⚙️ Carregando configurações de /etc/proxmox-postinstall.conf..."
    # Garante que as variáveis sejam carregadas para o shell atual
    source "/etc/proxmox-postinstall.conf"
    log_info "✅ Configurações carregadas."
else
    log_info "ℹ️ Arquivo de configuração /etc/proxmox-postinstall.conf não encontrado. Usando configurações padrão do script."
fi

# --- INÍCIO DA EXECUÇÃO DO SCRIPT ---

# 🔒 Prevenção de Múltiplas Execuções
if [ "$SKIP_LOCK" = false ] && [ -f "$LOCK_FILE" ]; then
    echo "⚠️ **ALERTA**: O script já foi executado anteriormente neste nó ($NODE_NAME). Abortando para evitar configurações duplicadas."
    echo "Se você realmente precisa re-executar, remova '$LOCK_FILE' ou use '--skip-lock' (NÃO RECOMENDADO)."
    exit 1
fi
touch "$LOCK_FILE" # Cria o arquivo de lock

log_info "📅 **INÍCIO**: Execução do script de pós-instalação no nó **$NODE_NAME** em $(date)"

---

### **Fase 1: Verificações Iniciais e Validação de Entrada**

log_info "🔍 Verificando dependências essenciais do sistema (curl, ping, nc)..."
check_dependency() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        echo "❌ **ERRO CRÍTICO**: O comando '$cmd' não foi encontrado. Por favor, instale-o (ex: apt install -y $cmd) e re-execute o script." | tee -a "$LOG_FILE"
        exit 1
    fi
    log_info "✅ Dependência '$cmd' verificada."
}
check_dependency "curl"
check_dependency "ping"
check_dependency "nc" # Netcat, usado para os testes de porta (apt install -y netcat-traditional ou netcat-openbsd)

log_info "🔍 Validando formato dos IPs e máscara de rede..."
# Validar cada IP do cluster
for ip in "${CLUSTER_PEER_IPS[@]}"; do
    validate_ip "$ip"
done
log_info "✅ Formato dos IPs em CLUSTER_PEER_IPS verificado."

# Validar formato da rede (ex: 172.20.220.0/24)
if ! [[ "$CLUSTER_NETWORK" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    log_info "❌ **ERRO**: Formato de rede inválido em CLUSTER_NETWORK. Use 'IP/MASK' (ex: 172.20.220.0/24)."
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
    echo "❌ **ERRO**: Este script requer Proxmox VE versão $REQUIRED_MAJOR_VERSION.x ou superior. Versão atual detectada: $PVE_VERSION. Não é compatível." | tee -a "$LOG_FILE"
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

---

### **Fase 2: Configuração de Tempo e NTP**

log_info "⏰ Configurando fuso horário para **$TIMEZONE** e sincronização NTP..."
log_cmd "timedatectl set-timezone $TIMEZONE"
log_cmd "timedatectl set-ntp true" # Habilita o systemd-timesyncd
log_cmd "systemctl restart systemd-timesyncd" # Garante que o serviço esteja rodando

log_info "Aguardando e verificando a sincronização NTP inicial..."
timeout 15 bash -c 'while ! timedatectl status | grep -q "System clock synchronized: yes"; do sleep 1; done'
if [ $? -ne 0 ]; then
    echo "⚠️ **AVISO**: Falha na sincronização NTP após 15 segundos! Tentando correção alternativa com ntpdate..." | tee -a "$LOG_FILE"
    # Garante que ntpdate esteja instalado antes de usá-lo
    command -v ntpdate &>/dev/null || log_cmd "apt install -y ntpdate"
    # Tenta sincronizar com ntpdate e registra qualquer erro, com múltiplos fallbacks
    ntpdate -s pool.ntp.org >> "$LOG_FILE" 2>&1 \
    || ntpdate -s 0.pool.ntp.org >> "$LOG_FILE" 2>&1 \
    || ntpdate -s 1.pool.ntp.org >> "$LOG_FILE" 2>&1 \
    || log_info '❌ **ERRO**: Falha grave ao sincronizar com ntpdate após várias tentativas. Verifique a conectividade de rede e as configurações de NTP.'
else
    log_info "✅ Sincronização NTP bem-sucedida."
fi

---

### **Fase 3: Gerenciamento de Repositórios e Atualizações**

log_info "🗑️ Desabilitando repositório de subscrição e habilitando repositório PVE no-subscription..."
# Faça backup de arquivos de lista de apt antes de modificar
backup_file "/etc/apt/sources.list.d/pve-enterprise.list"
backup_file "/etc/apt/sources.list"
backup_file "/etc/apt/sources.list.d/pve-no-subscription.list"

# Comenta a linha do pve-enterprise.list
log_cmd "sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list"
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

---

### **Fase 4: Configuração de Firewall**

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
log_cmd "pve-firewall stop"         # Parar o firewall para aplicar novas regras
log_cmd "pve-firewall rules --clean" # Limpa todas as regras existentes

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

# **CRÍTICO**: Regras para comunicação INTERNA DO CLUSTER (Corosync e pve-cluster)
# Essas regras são ABSOLUTAMENTE ESSENCIAIS para que os nós do cluster se comuniquem e funcionem corretamente.
log_info "Permitindo tráfego essencial para comunicação do cluster (Corosync, pve-cluster) na rede **$CLUSTER_NETWORK**..."
log_cmd "pve-firewall rule --add $CLUSTER_NETWORK --proto udp --dport 5404:5405 --accept --comment 'Corosync entre nós do cluster'"
log_cmd "pve-firewall rule --add $CLUSTER_NETWORK --proto tcp --dport 2224 --accept --comment 'pve-cluster entre nós do cluster'"

# Permitir tráfego ICMP (ping) entre os nós do cluster para facilitar diagnósticos
log_info "Permitindo tráfego ICMP (ping) na rede do cluster para facilitar diagnósticos futuros..."
log_cmd "pve-firewall rule --add $CLUSTER_NETWORK --proto icmp --accept --comment 'Permitir ping entre os nós do cluster'"

# Regra para permitir tráfego de SAÍDA para NTP (servidores externos)
log_info "Permitindo tráfego de saída para servidores NTP (porta UDP 123)..."
log_cmd "pve-firewall rule --action ACCEPT --direction OUT --proto udp --dport 123 --comment 'Permitir saída para NTP'"

# Regra final: Bloquear todo o tráfego não explicitamente permitido (default deny)
log_info "Aplicando regra de bloqueio padrão para todo o tráfego não autorizado..."
log_cmd "pve-firewall rule --add 0.0.0.0/0 --drop --comment 'Bloquear tráfego não autorizado por padrão'"

log_info "Ativando e iniciando o serviço de firewall do Proxmox VE..."
log_cmd "pve-firewall enable"
log_cmd "pve-firewall start"

---

### **Fase 5: Hardening de Segurança (Opcional)**

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

---

### **Fase 6: Instalação de Pacotes Opcionais**

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

---

### **Fase 7: Verificações Pós-Configuração e Finalização**

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
        log_info "❌ **FALHA**: Conexão Corosync com $PEER_IP (porta 5404) falhou. Verifique as regras de firewall e a rede."
    fi
    if nc -zv "$PEER_IP" 2224 &>/dev/null; then
        log_info "✅ Conexão pve-cluster com $PEER_IP (porta 2224) OK."
    else
        log_info "❌ **FALHA**: Conexão pve-cluster com $PEER_IP (porta 2224) falhou. Verifique as regras de firewall e a rede."
    fi
    # Teste de ping para a nova regra ICMP
    if ping -c 1 -W 1 "$PEER_IP" &>/dev/null; then
        log_info "✅ Ping com $PEER_IP OK."
    else
        log_info "❌ **FALHA**: Ping com $PEER_IP falhou. Verifique as regras de firewall (ICMP) e a conectividade de rede."
    fi
done

log_info "🌍 Testando conexão externa (internet) via HTTPS..."
if nc -zv google.com 443 &>/dev/null; then
    log_info "✅ Conexão externa via HTTPS (google.com:443) OK."
else
    log_info "⚠️ **AVISO**: Falha na conexão externa via HTTPS. Verifique as regras de saída do firewall e a conectividade geral com a internet."
fi

log_info "🧼 Limpando possíveis resíduos de execuções anteriores ou arquivos temporários..."
# Exemplo de remoção do hook de "no-nag-script" se ele não for mais desejado como permanente
# MANTENDO o hook, ele se auto-corrige. Se você quiser remover o hook completamente após a primeira execução:
# log_cmd "rm -f /etc/apt/apt.conf.d/no-nag-script"
log_info "✅ Limpeza de resíduos concluída."

log_info "🧹 Limpando logs de pós-instalação antigos (com mais de 15 dias) em /var/log/..."
# Encontra e remove logs mais antigos que 15 dias
log_cmd "find /var/log -name \"proxmox-postinstall-*.log\" -mtime +15 -exec rm {} \\;"
log_info "✅ Limpeza de logs antigos concluída."

# Cálculo do tempo total de execução
END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))

log_info "✅ **FINALIZADO**: Configuração concluída com sucesso no nó **$NODE_NAME** em $(date)."
log_info "⏳ Tempo total de execução do script: **$ELAPSED_TIME segundos**."
log_info "📋 O log detalhado de todas as operações está disponível em: **$LOG_FILE**."

---

### **Resumo da Configuração e Próximos Passos**

log_info "📝 **RESUMO DA CONFIGURAÇÃO E PRÓXIMOS PASSOS PARA SEU HOMELAB**"
log_info "---------------------------------------------------------"
log_info "✔️ Nó configurado: **$NODE_NAME**"
log_info "✔️ Firewall Proxmox VE ativo com regras para:"
log_info "    - Acesso ao WebUI (porta 8006) das redes internas"
log_info "    - Acesso SSH (porta 22) das redes internas"
log_info "    - Comunicação interna do cluster (Corosync: 5404-5405, pve-cluster: 2224) na rede '$CLUSTER_NETWORK'"
log_info "    - Ping (ICMP) entre os nós do cluster"
log_info "    - Acesso de saída para NTP e Internet (HTTPS)"
log_info "✔️ Hardening SSH (desativa login root por senha): $(grep -q "PermitRootLogin prohibit-password" /etc/ssh/sshd_config && echo "Aplicado" || echo "Não aplicado")"
log_info "✔️ NTP sincronizado: $(timedatectl show --property=NTPSynchronized --value && echo "Sim" || echo "Não")" # Verifica se NTP está sincronizado
log_info "✔️ Repositórios atualizados: No-Subscription Proxmox VE e Debian Bookworm"
log_info "---------------------------------------------------------"
log_info "🔍 **PRÓXIMOS PASSOS CRUCIAIS (MANUAIS)**:"
log_info "1.  **REINICIE O NÓ**: Algumas configurações (especialmente de rede e SSH) só terão efeito total após o reinício. **Isso é fundamental!**"
log_info "2.  **CRIE O CLUSTER (Primeiro Nó)**: No WebUI do seu primeiro nó, vá em **Datacenter > Cluster > Create Cluster**. Defina um nome para o cluster (ex: Aurora-Luna-Cluster)."
log_info "3.  **ADICIONE OUTROS NÓS AO CLUSTER**: Nos demais nós, no WebUI, vá em **Datacenter > Cluster > Join Cluster**. Use as informações do primeiro nó (token) para adicioná-los."
log_info "4.  **CONFIGURE STORAGES**: Após o cluster estar funcional, configure seus storages (LVM-Thin, ZFS, NFS, Ceph, etc.) conforme sua necessidade para armazenar VMs/CTs e ISOs."
log_info "5.  **CRIE CHAVES SSH (se aplicou hardening)**: Se você aplicou o hardening SSH, configure suas chaves SSH para acesso root antes de fechar a sessão atual, para garantir acesso futuro."
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
