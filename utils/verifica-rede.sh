#!/bin/bash
# verifica-rede.sh - Script para diagnosticar rede e serviços do Proxmox VE 8x
# Versão: 1.v1.0
# Autor: VIPs-com
# Data: 2025-06-02

# Configurações
LOG_DIR="/var/log/verifica-rede"
LOG_RETENTION_DAYS=7
DATE=$(date '+%Y-%m-%d_%H-%M-%S')
LOG_FILE="$LOG_DIR/verifica-rede-$DATE.log"
EXIT_STATUS=0

# Cria pasta de logs, se não existir
mkdir -p "$LOG_DIR"

# Funções de logging colorido e simples
log_info() {
    echo -e "\e[34m[INFO]\e[0m $1" | tee -a "$LOG_FILE"
}
log_success() {
    echo -e "\e[32m[SUCCESS]\e[0m $1" | tee -a "$LOG_FILE"
}
log_error() {
    echo -e "\e[31m[ERROR]\e[0m $1" | tee -a "$LOG_FILE"
    EXIT_STATUS=1
}
log_cabecalho() {
    echo -e "\n\e[36m==== $1 ====\e[0m" | tee -a "$LOG_FILE"
}

# Início do script
log_cabecalho "Início do diagnóstico - $(date)"

# 1. Verifica conectividade com IPs essenciais (exemplo: gateway e DNS)
IPS_ESSENCIAIS=("8.8.8.8" "192.168.0.1") # Ajuste conforme sua rede

log_cabecalho "1/5 - Verificando conectividade com IPs essenciais"
for ip in "${IPS_ESSENCIAIS[@]}"; do
    ping -c 3 -W 2 "$ip" &> /dev/null
    if [[ $? -eq 0 ]]; then
        log_success "Ping OK para $ip"
    else
        log_error "Falha no ping para $ip"
    fi
done

# 2. Testa resolução DNS
log_cabecalho "2/5 - Testando resolução DNS"
DNS_TEST_HOST="google.com"
nslookup $DNS_TEST_HOST &> /dev/null
if [[ $? -eq 0 ]]; then
    log_success "Resolução DNS funcionando para $DNS_TEST_HOST"
else
    log_error "Falha na resolução DNS para $DNS_TEST_HOST"
fi

# 3. Verifica portas importantes do Proxmox abertas (ex: 8006)
log_cabecalho "3/5 - Verificando portas TCP essenciais"
PORTAS=("8006" "22") # Adicione outras portas conforme necessidade

for porta in "${PORTAS[@]}"; do
    ss -tln | grep ":$porta " &> /dev/null
    if [[ $? -eq 0 ]]; then
        log_success "Porta TCP $porta está aberta"
    else
        log_error "Porta TCP $porta NÃO está aberta"
    fi
done

# 4. Verifica a interface de rede principal (ex: vmbr0)
log_cabecalho "4/5 - Verificando interface de rede vmbr0"
INTERFACE="vmbr0"
ip addr show "$INTERFACE" &> /dev/null
if [[ $? -eq 0 ]]; then
    log_success "Interface $INTERFACE existe"
    IP_ATRIBUIDO=$(ip -4 addr show "$INTERFACE" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    log_info "IP atribuído à $INTERFACE: $IP_ATRIBUIDO"
else
    log_error "Interface $INTERFACE NÃO encontrada"
fi

# 5. Verificação dos Serviços Essenciais do Proxmox VE
log_cabecalho "5/5 - Verificando Serviços Essenciais do Proxmox VE"
SERVICOS=("corosync" "pve-cluster" "pvedaemon" "pvestatd" "pveproxy")

for servico in "${SERVICOS[@]}"; do
    systemctl is-active --quiet "$servico"
    if [[ $? -eq 0 ]]; then
        log_success "Serviço '$servico' está ativo."
    else
        log_error "Serviço '$servico' NÃO está ativo."
    fi
done

# Limpeza de logs antigos
log_cabecalho "Limpando logs antigos (mais de $LOG_RETENTION_DAYS dias)"
find "$LOG_DIR" -type f -name "verifica-rede-*.log" -mtime +"$LOG_RETENTION_DAYS" -exec rm -f {} \;
log_info "Arquivos de log com mais de $LOG_RETENTION_DAYS dias removidos."

# Finaliza com status
if [[ $EXIT_STATUS -eq 0 ]]; then
    log_success "Diagnóstico concluído sem erros. Tudo OK!"
else
    log_error "Diagnóstico concluído com problemas. Verifique os logs para detalhes."
fi

exit $EXIT_STATUS
