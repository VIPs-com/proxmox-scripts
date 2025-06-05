#!/usr/bin/env bash

# 🚀 Script Pós-Instalação Proxmox VE 8 - Cluster Aurora/Luna
# Autor: VIPs-com
# Versão: 1.2.2
# Data: 2025-06-05
#
# Este script DEVE SER EXECUTADO INDIVIDUALMENTE em cada nó do cluster Proxmox.
# A configuração do Firewall agora está em um script separado: proxmox-firewall-config.sh
#
# 🔥 PRÉ-REQUISITO CRÍTICO:
#    Execute o 'diagnostico-proxmox-ambiente.sh' ANTES deste script para validar o ambiente.
#    Ex: ./diagnostico-proxmox-ambiente.sh && ./proxmox-postinstall-aurora-luna.sh
#
# 📌 ORDEM DE EXECUÇÃO DO CLUSTER (MANUAL VIA WEBUI):
#    Este script assume que o cluster JÁ FOI CRIADO ou será criado MANUALMENTE via WebUI.
#    1. Crie o cluster no primeiro nó (Datacenter > Cluster > Create Cluster).
#    2. Junte os outros nós ao cluster (Datacenter > Cluster > Join Cluster).
#    3. SOMENTE DEPOIS execute este script em CADA NÓ.
#
######
#
# 🔹 VLANs Utilizadas (referência para as regras de firewall):
#    - 172.20.220.0/24 (Home Lab - Rede principal para comunicação do cluster)
#    - 172.21.221.0/24 (Rede Interna - Gerenciamento)
#    - 172.25.125.0/24 (Wi-Fi Arkadia)


# 🛠️ CONFIGURAÇÕES ESSENCIAIS (AJUSTE CONFORME SUA INFRAESTRUTURA)
# Podem ser sobrescritas por /etc/proxmox-postinstall.conf
CLUSTER_NETWORK="172.20.220.0/24" # Rede para comunicação interna do cluster (Corosync, pve-cluster)
NODE_NAME=$(hostname)             # Nome do servidor atual
TIMEZONE="America/Sao_Paulo"     # Fuso horário do sistema

# IPs de outros nós do cluster para testes de conectividade pós-configuração.
# Adicione TODOS os IPs dos seus nós aqui. O script ignorará o IP do próprio nó durante o teste.
# Exemplo: Se seus nós são 172.20.220.20 (Aurora) e 172.20.220.21 (Luna):
CLUSTER_PEER_IPS=("172.20.220.20" "172.20.220.21")

# Arquivos de log e lock
LOG_FILE="/var/log/proxmox-postinstall-$(date +%Y%m%d)-$(hostname).log"
LOCK_FILE="/etc/proxmox-postinstall.lock"
START_TIME=$(date +%s) # Início do registro de tempo de execução

# --- Configuração de Robustez ---
set -e # Sai imediatamente se um comando falhar.
# set -u # Sai se uma variável não definida for usada (opcional, pode ser muito rigoroso).

# --- FUNÇÕES DE LOG E AUXILIARES ---
# Cores para a saída no terminal
VERMELHO='\033[0;31m'
VERDE='\033[0;32m'
AMARELO='\033[1;33m'
CIANO='\033[0;36m'
ROXO='\033[0;35m' # Cor para cabeçalhos de fase
SEM_COR='\033[0m' # Resetar cor

# Variável de status geral do script (0 = OK, 1 = ERRO)
overall_script_status=0

# Funções de log padronizadas
log_cabecalho_fase() { echo -e "\n${ROXO}=== FASE: $1 ===${SEM_COR}" | tee -a "$LOG_FILE"; }
log_info() { echo -e "ℹ️  ${CIANO}$@${SEM_COR}" | tee -a "$LOG_FILE"; }
log_ok() { echo -e "✅ ${VERDE}$@${SEM_COR}" | tee -a "$LOG_FILE"; }
log_erro() { echo -e "❌ ${VERMELHO}$@${SEM_COR}" | tee -a "$LOG_FILE"; overall_script_status=1; }
log_aviso() { echo -e "⚠️  ${AMARELO}$@${SEM_COR}" | tee -a "$LOG_FILE"; }

# Função para executar comandos e logar o status
executar_comando() {
    local cmd="$@"
    log_info "Executando: $cmd"
    # Captura a saída do comando para o log, e o status de saída.
    if eval "$cmd" >> "$LOG_FILE" 2>&1; then
        log_ok "Comando executado com sucesso."
        return 0 # Sucesso
    else
        local status=$?
        log_erro "Falha [$status] ao executar: $cmd"
        return 1 # Falha
    fi
}

# Função para fazer backup de arquivos
backup_arquivo() {
    local arquivo="$1"
    if [ -f "$arquivo" ]; then
        local dir_backup="/var/backups/proxmox-postinstall"
        executar_comando "mkdir -p $dir_backup" || return 1
        local timestamp=$(date +%Y%m%d%H%M%S)
        local caminho_backup="$dir_backup/$(basename "$arquivo").${timestamp}"
        log_info "📦 Fazendo backup de '$arquivo' para '$caminho_backup'..."
        executar_comando "cp -p $arquivo $caminho_backup" || { log_aviso "Falha ao criar backup de '$arquivo'."; return 1; }
        log_ok "Backup de '$arquivo' criado com sucesso."
    else
        log_info "ℹ️ Arquivo '$arquivo' não encontrado, nenhum backup necessário."
    fi
    return 0
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
        *) log_erro "Opção inválida: $arg. Use -h ou --help para ver as opções."; exit 1 ;;
    esac
done

# Carrega configurações de arquivo externo (se existir)
if [ -f "/etc/proxmox-postinstall.conf" ]; then
    log_info "⚙️ Carregando configurações de /etc/proxmox-postinstall.conf..."
    # Garante que as variáveis sejam carregadas para o shell atual
    source "/etc/proxmox-postinstall.conf"
    log_ok "Configurações carregadas."
else
    log_info "ℹ️ Arquivo de configuração /etc/proxmox-postinstall.conf não encontrado. Usando configurações padrão do script."
fi

# --- INÍCIO DA EXECUÇÃO DO SCRIPT ---
# 🔒 Prevenção de Múltiplas Execuções
if [ "$SKIP_LOCK" = false ] && [ -f "$LOCK_FILE" ]; then
    log_erro "O script já foi executado anteriormente neste nó ($NODE_NAME). Abortando para evitar configurações duplicadas."
    log_info "Se você realmente precisa re-executar, remova '$LOCK_FILE' ou use '--skip-lock' (NÃO RECOMENDADO)."
    exit 1
fi
executar_comando "touch $LOCK_FILE" || { log_erro "Falha ao criar arquivo de lock."; exit 1; }

log_info "📅 INÍCIO: Execução do script de pós-instalação no nó $NODE_NAME em $(date)"

# --- DEFINIÇÃO DAS FASES (FUNÇÕES) ---

# Fase 1: Configuração de Tempo e NTP
configurar_tempo_ntp() {
    log_cabecalho_fase "1/4 - Configuração de Tempo e NTP"
    log_info "Configurando fuso horário para $TIMEZONE e sincronização NTP..."
    executar_comando "timedatectl set-timezone $TIMEZONE" || return 1
    executar_comando "timedatectl set-ntp true" || return 1 # Habilita o systemd-timesyncd

    # Desabilita o serviço ntp se estiver ativo para evitar conflitos com systemd-timesyncd
    if systemctl is-active --quiet ntp; then
        log_info "Serviço 'ntp' detectado e ativo. Desabilitando para evitar conflito com systemd-timesyncd."
        executar_comando "systemctl stop ntp" || log_aviso "Falha ao parar o serviço 'ntp'."
        executar_comando "systemctl disable ntp" || log_aviso "Falha ao desabilitar o serviço 'ntp'."
    fi

    executar_comando "systemctl restart systemd-timesyncd" || return 1 # Garante que o serviço esteja rodando

    log_info "Aguardando e verificando a sincronização NTP inicial..."
    timeout 20 bash -c 'while ! timedatectl status | grep -q "System clock synchronized: yes"; do sleep 1; done'
    if [ $? -ne 0 ]; then
        log_aviso "Falha na sincronização NTP após 20 segundos! Verifique a conectividade com servidores NTP."
        # Tenta sincronizar manualmente com ntpdate como fallback se timedatectl falhar.
        if ! command -v ntpdate &>/dev/null; then
            log_info "Instalando ntpdate para tentativa de sincronização manual..."
            executar_comando "apt update && apt install -y ntpdate" || log_aviso "Falha ao instalar ntpdate."
        fi
        if command -v ntpdate &>/dev/null; then
            log_info "Tentando sincronizar com ntpdate e pool.ntp.org..."
            if ! ntpdate -s pool.ntp.org >> "$LOG_FILE" 2>&1; then
                log_erro 'Falha grave ao sincronizar com ntpdate após várias tentativas. Verifique a conectividade de rede e as configurações de NTP.'
                return 1
            else
                log_ok "Sincronização NTP alternativa com ntpdate concluída (verifique o status)."
            fi
        fi
    else
        log_ok "Sincronização NTP bem-sucedida."
    fi
    return 0
}

# Fase 2: Gerenciamento de Repositórios e Atualizações
gerenciar_repositorios_atualizacoes() {
    log_cabecalho_fase "2/4 - Gerenciamento de Repositórios e Atualizações"
    log_info "Desabilitando repositório de subscrição e habilitando repositório PVE no-subscription..."
    backup_arquivo "/etc/apt/sources.list.d/pve-enterprise.list"
    backup_arquivo "/etc/apt/sources.list"
    backup_arquivo "/etc/apt/sources.list.d/pve-no-subscription.list"

    # CORREÇÃO CRÍTICA: Garante que o comando sed só seja executado se o arquivo existir
    if [ -f "/etc/apt/sources.list.d/pve-enterprise.list" ]; then
        log_info "Comentando a linha do pve-enterprise.list para desabilitar o repositório de subscrição."
        executar_comando "sed -i 's/^deb/#deb/' /etc/apt/sources.list.d/pve-enterprise.list" || return 1
    else
        log_info "ℹ️ Arquivo /etc/apt/sources.list.d/pve-enterprise.list não encontrado. Nenhuma ação necessária para desabilitar o repositório de subscrição."
    fi

    executar_comando "echo 'deb http://ftp.debian.org/debian bookworm main contrib' > /etc/apt/sources.list" || return 1
    executar_comando "echo 'deb http://ftp.debian.org/debian bookworm-updates main contrib' >> /etc/apt/sources.list" || return 1
    executar_comando "echo 'deb http://security.debian.org/debian-security bookworm-security main contrib' >> /etc/apt/sources.list" || return 1
    executar_comando "echo 'deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription' > /etc/apt/sources.list.d/pve-no-subscription.list" || return 1

    log_info "Atualizando listas de pacotes e o sistema operacional..."
    executar_comando "apt update" || return 1
    executar_comando "apt dist-upgrade -y" || return 1 # Atualiza todos os pacotes e resolve dependências
    executar_comando "apt autoremove -y" || return 1    # Remove pacotes órfãos
    executar_comando "apt clean" || return 1            # Limpa o cache de pacotes
    log_ok "Sistema atualizado."

    log_info "Removendo o aviso de assinatura Proxmox VE do WebUI (se não possuir uma licença ativa)..."
    # Cria um hook para APT que modifica o arquivo JS do WebUI
    executar_comando "echo \"DPkg::Post-Invoke { \\\"dpkg -V proxmox-widget-toolkit | grep -q '/proxmoxlib.js$'; if [ \\\$? -eq 1 ]; then sed -i '/.*data.status.*{/{s/\\!//;s/active/NoMoreNagging/}' /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js; fi\\\"; };\" > /etc/apt/apt.conf.d/no-nag-script" || return 1
    executar_comando "apt --reinstall install -y proxmox-widget-toolkit" || return 1
    log_ok "Aviso de assinatura removido do WebUI (se aplicável)."
    return 0
}

# Fase 3: Hardening de Segurança SSH
aplicar_hardening_ssh() {
    log_cabecalho_fase "3/4 - Hardening de Segurança SSH (Opcional)"
    echo
    read -p "🔒 Deseja aplicar hardening de segurança (desativar login de root por senha e password authentication)? [s/N] " -n 1 -r -t 10
    echo # Nova linha após a resposta
    REPLY=${REPLY:-N}
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        log_info "Aplicando hardening SSH..."
        backup_arquivo "/etc/ssh/sshd_config"
        executar_comando "sed -i 's/^#\\?PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config" || return 1
        executar_comando "sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config" || return 1
        executar_comando "systemctl restart sshd" || return 1
        log_ok "Hardening aplicado! Atenção: Agora, o acesso ao root via SSH só será possível usando chaves SSH. Certifique-se de tê-las configuradas antes de fechar a sessão atual."
    else
        log_info "Hardening SSH ignorado. O login por senha permanece ativo (menos seguro para produção)."
    fi
    return 0
}

# Fase 4: Instalação de Pacotes Opcionais
instalar_pacotes_opcionais() {
    log_cabecalho_fase "4/4 - Instalação de Pacotes Opcionais"
    echo
    read -p "📦 Deseja instalar ferramentas adicionais úteis (ex: qemu-guest-agent, ifupdown2, git, htop, smartmontools)? [s/N] " -n 1 -r -t 10
    echo # Nova linha após a resposta
    REPLY=${REPLY:-N}
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        log_info "Instalando pacotes adicionais..."
        executar_comando "apt install -y qemu-guest-agent ifupdown2 git htop smartmontools" || return 1
        log_ok "Pacotes adicionais instalados."
    else
        log_info "Instalação de pacotes adicionais ignorada."
    fi
    return 0
}

# --- FUNÇÃO AUXILIAR PARA TESTE DE CONECTIVIDADE (USADA NAS VERIFICAÇÕES PÓS-CONFIG) ---
# Esta função foi movida para cá para ser usada SOMENTE nas verificações finais,
# pois as verificações iniciais são feitas pelo 'diagnostico-proxmox-ambiente.sh'.
# Uso: test_port_connectivity <IP> <PORTA> [tcp|udp]
test_port_connectivity() {
    local ip=$1
    local port=$2
    local proto=${3:-tcp} # Padrão é TCP se não especificado.
    local result=1

    if [[ "$proto" == "tcp" ]]; then
        timeout 2 bash -c "cat < /dev/null > /dev/tcp/$ip/$port" 2>/dev/null
        result=$?
    elif [[ "$proto" == "udp" ]]; then
        timeout 2 nc -uz "$ip" "$port" 2>/dev/null
        result=$?
    fi
    return $result
}


# --- EXECUÇÃO PRINCIPAL DAS FASES ---
# Array de funções a serem executadas. O script para se uma função retornar falha (1).
declare -a FASES=(
    "configurar_tempo_ntp"
    "gerenciar_repositorios_atualizacoes"
    "aplicar_hardening_ssh"
    "instalar_pacotes_opcionais"
)

for fase_func in "${FASES[@]}"; do
    if ! "$fase_func"; then
        log_erro "A fase '$fase_func' falhou. Abortando script."
        exit 1 # Sai do script principal se uma fase falhar
    fi
done

# --- VERIFICAÇÕES PÓS-CONFIGURAÇÃO E FINALIZAÇÃO ---
log_cabecalho_fase "Verificações Pós-Configuração e Finalização"

log_info "🔍 Verificando status de serviços críticos do Proxmox VE..."
if ! systemctl is-active corosync pve-cluster pvedaemon; then
    log_erro "Um ou mais serviços críticos do Proxmox (corosync, pve-cluster, pvedaemon) NÃO estão ativos. Verifique os logs e tente reiniciar manualmente."
    log_info "O script será encerrado devido à falha de serviço crítico."
    exit 1
else
    log_ok "✅ Todos os serviços críticos do Proxmox VE (corosync, pve-cluster, pvedaemon) estão ativos."
fi

log_info "🔗 Realizando testes de conectividade essencial do cluster com nós pares (após configuração inicial)..."
log_info "⚠️ NOTA: A conectividade pode ser afetada se o script de firewall separado ainda não foi executado."
for PEER_IP in "${CLUSTER_PEER_IPS[@]}"; do
    # Obtém o IP principal do próprio nó para evitar testar a si mesmo
    CURRENT_NODE_IP=$(hostname -I | awk '{print $1}') # Pega o primeiro IP local

    if [ "$PEER_IP" = "$CURRENT_NODE_IP" ]; then
        continue # Pula o teste se o IP for o do próprio nó
    fi

    log_info "Testando conexão com o nó $PEER_IP..."
    # Teste para portas Corosync (UDP) - Estas portas devem estar abertas para comunicação do cluster
    if test_port_connectivity "$PEER_IP" 5404 "udp"; then
        log_ok "Conexão Corosync com $PEER_IP (porta 5404 UDP) OK."
    else
        log_erro "FALHA: Conexão Corosync com $PEER_IP (porta 5404 UDP) falhou. Verifique as regras de firewall e a conectividade de rede."
    fi
    if test_port_connectivity "$PEER_IP" 5405 "udp"; then
        log_ok "Conexão Corosync com $PEER_IP (porta 5405 UDP) OK."
    else
        log_erro "FALHA: Conexão Corosync com $PEER_IP (porta 5405 UDP) falhou. Verifique as regras de firewall e a conectividade de rede."
    fi
    if test_port_connectivity "$PEER_IP" 5406 "udp"; then
        log_ok "Conexão Corosync com $PEER_IP (porta 5406 UDP) OK."
    else
        log_erro "FALHA: Conexão Corosync com $PEER_IP (porta 5406 UDP) falhou. Verifique as regras de firewall e a conectividade de rede."
    fi
    if test_port_connectivity "$PEER_IP" 5407 "udp"; then
        log_ok "Conexão Corosync com $PEER_IP (porta 5407 UDP) OK."
    else
        log_erro "FALHA: Conexão Corosync com $PEER_IP (porta 5407 UDP) falhou. Verifique as regras de firewall e a conectividade de rede."
    fi

    # Teste para porta pve-cluster (TCP)
    if test_port_connectivity "$PEER_IP" 2224 "tcp"; then
        log_ok "Conexão pve-cluster com $PEER_IP (porta 2224 TCP) OK."
    else
        log_erro "FALHA: Conexão pve-cluster com $PEER_IP (porta 2224 TCP) falhou. Verifique as regras de firewall e a conectividade de rede."
    fi

    # Teste de ping
    if ping -c 1 -W 1 "$PEER_IP" &>/dev/null; then
        log_ok "Ping com $PEER_IP OK."
    else
        log_aviso "Ping com $PEER_IP falhou. Isso pode ser esperado se as regras de ICMP ainda não foram aplicadas pelo script de firewall."
    fi
done

log_info "🌍 Testando conexão externa (internet) via HTTPS..."
if nc -zv google.com 443 &>/dev/null; then
    log_ok "Conexão externa via HTTPS (google.com:443) OK."
else
    log_aviso "Falha na conexão externa via HTTPS. Verifique a conectividade geral com a internet."
fi

log_info "🧼 Limpando possíveis resíduos de execuções anteriores ou arquivos temporários..."
log_ok "Limpeza de resíduos concluída."

log_info "🧹 Limpando logs de pós-instalação antigos (com mais de 15 dias) em /var/log/..."
executar_comando "find /var/log -name \"proxmox-postinstall-*.log\" -mtime +15 -exec rm {} \\;" || log_aviso "Falha na limpeza de logs antigos."
log_ok "Limpeza de logs antigos concluída."

# Cálculo do tempo total de execução
END_TIME=$(date +%s)
ELAPSED_TIME=$((END_TIME - START_TIME))

log_info "✅ **FINALIZADO**: Configuração inicial do nó **$NODE_NAME** concluída em $(date)."
log_info "⏳ Tempo total de execução do script: **$ELAPSED_TIME segundos**."
log_info "📋 O log detalhado de todas as operações está disponível em: **$LOG_FILE**."

# --- Resumo da Configuração e Próximos Passos ---
log_cabecalho_fase "RESUMO DA CONFIGURAÇÃO E PRÓXIMOS PASSOS"
log_info "📝 **RESUMO DA CONFIGURAÇÃO E PRÓXIMOS PASSO PARA SEU HOMELAB**"
log_info "---------------------------------------------------------"
log_info "✔️ Nó configurado: **$NODE_NAME**"
log_info "✔️ Firewall Proxmox VE: As regras de firewall DEVEM ser configuradas separadamente com o script `proxmox-firewall-config.sh`."
log_info "✔️ Hardening SSH (desativa login root por senha): $(grep -q "PermitRootLogin prohibit-password" /etc/ssh/sshd_config && echo "Aplicado" || echo "Não aplicado")"
log_info "✔️ NTP sincronizado: $(timedatectl show --property=NTPSynchronized --value && echo "Sim" || echo "Não")"
log_info "✔️ Repositórios atualizados: No-Subscription Proxmox VE e Debian Bookworm"
log_info "---------------------------------------------------------"
log_info "🔍 LEMBRETE IMPORTANTE DE FLUXO:"
log_info "    Este script foi executado APÓS a criação manual do cluster via WebUI (se aplicável)."
log_info "    Isso garante que as chaves e certificados do cluster foram gerados corretamente."
log_info "---------------------------------------------------------"
log_info "👉 PRÓXIMOS PASSOS CRUCIAIS (MANUAIS):"
log_info "1.  **REINICIE O NÓ**: Algumas configurações (especialmente de rede e SSH) só terão efeito total após o reinício. **Isso é fundamental!**"
log_info "2.  **ACESSE O WEBUI**: Se você ainda não fez, acesse o WebUI de um dos nós para verificar o status do cluster e das configurações:"
log_info "    - Ex: https://172.20.220.20:8006"
log_info "3.  **CONFIGURE O FIREWALL**: Execute o script `proxmox-firewall-config.sh` em CADA NÓ. **Isso é CRÍTICO para a segurança e funcionalidade da rede!**"
log_info "4.  **CONFIGURE STORAGES**: Após o cluster estar funcional e os nós reiniciados, configure seus storages (LVM-Thin, ZFS, NFS, Ceph, etc.) conforme sua necessidade para armazenar VMs/CTs e ISOs."
log_info "5.  **CRIE CHAVES SSH (se aplicou hardening)**: Se você optou por aplicar o hardening SSH, configure suas chaves SSH para acesso root *antes* de fechar a sessão atual, para garantir acesso futuro."
log_info "6.  **VERIFIQUE O DIAGNÓSTICO NOVAMENTE**: Execute o 'diagnostico-proxmox-ambiente.sh' novamente para confirmar que todas as pendências foram resolvidas."
log_info "---------------------------------------------------------"

# --- REINÍCIO RECOMENDADO ---
echo
read -p "⟳ **REINÍCIO ALTAMENTE RECOMENDADO**: Para garantir que todas as configurações sejam aplicadas, é **fundamental** reiniciar o nó. Deseja reiniciar agora? [s/N] " -n 1 -r -t 15
echo # Adiciona uma nova linha após a resposta do usuário ou timeout

# Define 'N' como padrão se nada for digitado ou se houver timeout
REPLY=${REPLY:-N}

if [[ $REPLY =~ ^[Ss]$ ]]; then
    log_info "🔄 Reiniciando o nó **$NODE_NAME** agora..."
    executar_comando "reboot" || log_erro "Falha ao iniciar o reboot."
else
    log_info "ℹ️ Reinício adiado. Lembre-se de executar 'reboot' manualmente no nó **$NODE_NAME** o mais rápido possível para aplicar todas as mudanças."
fi

exit "$overall_script_status" # Retorna o status geral do script
