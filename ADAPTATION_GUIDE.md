# ⚙️ Guia de Adaptação para Outros Ambientes  
**Versão Otimizada — postinstall-aurora-luna.sh**

Este guia explica como adaptar o script de pós-instalação `postinstall-aurora-luna.sh` para funcionar corretamente em ambientes diferentes da configuração padrão do cluster Aurora/Luna (rede `172.20.220.0/24`).

Ele ajuda a identificar rapidamente as partes do script que exigem modificação, como endereços IP, sub-redes, VLANs e repositórios, além de orientações sobre validações e problemas comuns.

---

## 📌 Sumário

1. [Variáveis de Rede Iniciais](#1-variáveis-de-rede-iniciais)  
2. [Regras de Firewall](#2-regras-de-firewall-acesso-ao-webui-ssh-e-vlans)  
3. [Repositórios APT (Proxy ou Internos)](#3-repositórios-apt-uso-de-proxies-ou-internos---opcional)  
4. [Verificações Pós-Adaptação](#4-verificações-pós-adaptação)  
5. [Problemas Comuns na Adaptação](#5-problemas-comuns-na-adaptação)  

> ⚠️ **IMPORTANTE:** Sempre revise todas as alterações antes de executar o script. Faça testes em ambiente de homologação, sempre que possível.

---

## 1. Variáveis de Rede Iniciais

Logo no início do script (linhas ~15 a 45), localize as seguintes variáveis e ajuste conforme o seu ambiente:

### 🔸 `CLUSTER_NETWORK`
Define a sub-rede principal para comunicação interna (Corosync).

```bash
# Exemplo original:
# CLUSTER_NETWORK="172.20.220.0/24"

# Adaptação para rede 192.168.1.0/24:
CLUSTER_NETWORK="192.168.1.0/24"
```

### 🔸 `CLUSTER_PEER_IPS`
Lista de IPs dos nós do cluster. Serve para testes de conectividade e firewall.

```bash
# Exemplo original:
# CLUSTER_PEER_IPS=("172.20.220.20" "172.20.220.21")

# Adaptação:
CLUSTER_PEER_IPS=("192.168.1.10" "192.168.1.11")
```

### 🔸 `TIMEZONE`
Fuso horário do sistema.

```bash
# Exemplo original:
# TIMEZONE="America/Sao_Paulo"

# Adaptação (exemplo para Nova York):
TIMEZONE="America/New_York"
```

---

## 2. Regras de Firewall (Acesso ao WebUI, SSH e VLANs)

As regras de firewall (linhas ~60 a 120) controlam o acesso ao Proxmox WebUI, SSH e tráfego interno. Altere os blocos `pve-firewall rule` e `localnet` conforme suas redes.

### 🔸 Exemplo de Regra WebUI:

```bash
# Original:
# pve-firewall rule --add 172.20.220.0/24 --proto tcp --dport 8006 --accept

# Adaptado:
pve-firewall rule --add 192.168.1.0/24 --proto tcp --dport 8006 --accept --comment 'Acesso WebUI da Minha Rede'
```

### 🔸 Exemplo para SSH:

```bash
pve-firewall rule --add 192.168.1.0/24 --proto tcp --dport 22 --accept --comment 'Acesso SSH da Minha Rede'
```

### 🔸 Definição de Redes Locais (`localnet`):

```bash
pve-firewall localnet --add 192.168.1.0/24 --comment 'Minha VLAN de Cluster'
```

> Se você tiver múltiplas VLANs, adicione regras semelhantes para cada sub-rede.

---

## 3. Repositórios APT (Uso de Proxies ou Internos — Opcional)

Por padrão, o script usa repositórios públicos. Se você usa **proxy** ou **mirror local**, edite essas seções.

### 🔸 Usando Proxy HTTP:

```bash
export http_proxy="http://meuproxy.local:8080"
export https_proxy="http://meuproxy.local:8080"
echo 'Acquire::http::Proxy "http://meuproxy.local:8080";' > /etc/apt/apt.conf.d/00proxy
```

### 🔸 Usando Mirror Interno:

Substitua as URLs dos repositórios por seus espelhos internos:

```bash
log_cmd "echo 'deb http://mirror.local/debian bookworm main contrib' > /etc/apt/sources.list"
log_cmd "echo 'deb http://mirror.local/pve bookworm pve-no-subscription' > /etc/apt/sources.list.d/pve-no-subscription.list"
```

---

## 4. Verificações Pós-Adaptação

Antes de rodar o script no ambiente final, valide os ajustes.

### 🔸 Testar Conectividade entre Nós:

```bash
ping ${CLUSTER_PEER_IPS[0]}
```

✅ Esperado: Resposta ICMP normal.

### 🔸 Compilar e Verificar Regras de Firewall:

```bash
pve-firewall compile
```

✅ Esperado: Nenhuma mensagem de erro.

### 🔸 Testar Atualização de Pacotes:

```bash
apt update
```

✅ Esperado: Repositórios acessíveis sem erros.

---

## 5. Problemas Comuns na Adaptação

| ❌ Sintoma                              | 🛠️ Solução                                                                 |
|----------------------------------------|----------------------------------------------------------------------------|
| Não acessa WebUI (`https://IP:8006`)  | Verifique se a porta 8006 está liberada para sua rede (firewall).         |
| Cluster não forma ou perde nós         | Revise `CLUSTER_NETWORK`, verifique conectividade e portas UDP 5404–5405. |
| Horário incorreto / NTP falha         | Verifique se UDP 123 está liberado e o fuso horário correto foi definido. |
| `apt update` falha                    | Confirme os repositórios (ou proxy) e conectividade de rede.              |

---

## 🚀 Conclusão

Com esse guia, adaptar o script `postinstall-aurora-luna.sh` para sua própria rede se torna simples e seguro. Mantenha sempre uma versão do script personalizada para seu ambiente e utilize este guia como referência sempre que necessário.

---

## 📘 Como Adicionar este Guia ao Repositório

1. No seu GitHub, vá em **VIPs-com/proxmox-scripts**.  
2. Clique em **"Add file" > "Create new file"**.  
3. Nomeie como: `ADAPTATION_GUIDE.md`.  
4. Cole este conteúdo.  
5. Clique em **"Commit new file"**.

### ➕ Adicione o Link no README.md

Edite seu `README.md` e, na seção de documentação, inclua:

```markdown
### 📚 Documentação & Recursos

- 🔧 [Guia de Adaptação do Script (ADAPTATION_GUIDE.md)](./ADAPTATION_GUIDE.md)
```
