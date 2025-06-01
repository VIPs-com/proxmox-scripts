# 🚀 Proxmox Scripts - Cluster Aurora/Luna

![Proxmox Version](https://img.shields.io/badge/Proxmox-8.x-orange)
![Version](https://img.shields.io/github/v/release/VIPs-com/proxmox-scripts?include_prereleases)
![CHANGELOG](https://img.shields.io/badge/CHANGELOG-auto--updated-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)

> Scripts de automação para servidores Proxmox VE no cluster Aurora/Luna

---

## 📌 Script de Pós-Instalação

**`postinstall-aurora-luna.sh`** - Configura automaticamente os nós:
- **Aurora** (`172.20.220.20`)
- **Luna** (`172.20.220.21`)

### 🔥 Recursos Principais

- 🛡️ Configuração automática de firewall  
- 🔒 Hardening SSH  
- ⏱ Sincronização NTP  
- 🌐 Suporte às VLANs:

| VLAN             | Propósito         |
|------------------|-------------------|
| `172.20.220.0/24`| Cluster principal |
| `172.21.221.0/24`| Gerenciamento     |
| `172.25.125.0/24`| Rede Wi-Fi        |

---
### 📚 Documentação & Recursos

- 🔧 [Guia de Adaptação do Script (ADAPTATION_GUIDE.md)](./ADAPTATION_GUIDE.md)

---
## 🚀 Como Instalar

```bash
# Método com curl (recomendado):
curl -sL https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/proxmox-postinstall-aurora-luna.sh | bash

# Método com wget:
wget https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/proxmox-postinstall-aurora-luna.sh
chmod +x proxmox-postinstall-aurora-luna.sh
sudo ./proxmox-postinstall-aurora-luna.sh
```

---

## 🔗 Links Úteis

- [Acessar Aurora WebUI](https://172.20.220.20:8006)  
- [Acessar Luna WebUI](https://172.20.220.21:8006)  
- [Ver histórico de alterações](https://github.com/VIPs-com/proxmox-scripts/releases)  
- [Workflow de automação](https://github.com/VIPs-com/proxmox-scripts/actions)  

---

## ⚡ DICA IMPORTANTE

Após rodar o script e reiniciar o nó, execute o comando abaixo para validar a performance do sistema:

```bash
pveperf
```

---

<!--
## 🎥 Demonstração

*Em breve: GIF ou vídeo curto mostrando a execução do script.*

![Exemplo de Execução](link-do-gif-ou-screenshot.gif)
-->

---

## 🤝 Como Contribuir

```bash
# 1. Clone o repositório
git clone https://github.com/VIPs-com/proxmox-scripts.git

# 2. Crie uma branch
git checkout -b minha-feature

# 3. Faça e commit suas alterações
git commit -m "Minha contribuição"

# 4. Envie para o repositório
git push origin minha-feature
```

---

## ❓ FAQ - Problemas Comuns

### 🔹 Erro: "Falha ao juntar nó no cluster"

✅ Solução: Verifique se o firewall permite o tráfego Corosync (`UDP 5404-5405`).  
✅ Teste rápido:  

```bash
nc -zv 172.20.220.20 5404
```

---

### 🔹 Erro: "Permissão negada ao rodar script"

✅ Solução: Torne o script executável com:  

```bash
chmod +x nome-do-script.sh
```

---

### 🔹 Erro: "Comando pveperf não encontrado"

✅ Solução: Certifique-se que o Proxmox VE está instalado e atualizado corretamente no nó.

---

**Contribuições e sugestões são sempre bem-vindas!**

---

## 🛠️ Ferramentas de Diagnóstico

### 🔍 Script de Verificação de Rede

**Arquivo:** `utils/verifica-rede.sh`

**Funcionalidades:**
- 📶 Teste de latência entre nós
- 🔌 Verificação de portas essenciais (SSH, WebUI, Corosync)
- 🌐 Checagem de DNS reverso

**Como Usar:**
```bash
# Execução direta via curl:
bash <(curl -s https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/utils/verifica-rede.sh)

# Ou baixar e executar localmente:
mkdir -p utils
wget -O utils/verifica-rede.sh https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/utils/verifica-rede.sh
chmod +x utils/verifica-rede.sh
./utils/verifica-rede.sh
```

**Exemplo de Saída:**
```
🔍 Diagnóstico de Rede - [Data]
----------------------------------------
ℹ️  1/3 - Medição de Latência:
✅ 172.20.220.20 → Latência média: 1.245ms
✅ 172.20.220.21 → Latência média: 2.817ms

ℹ️  2/3 - Verificando portas:
🔧 Nó 172.20.220.20:
✅ Porta 22 → Acessível
✅ Porta 8006 → Acessível

ℹ️  3/3 - Verificando DNS:
✅ 172.20.220.20 → proxmox01.local
❌ 172.20.220.21 → Sem resolução reversa

📊 Resultado Final:
❌ Problemas detectados
ℹ️  Recomendação: Resolva os itens em vermelho
----------------------------------------
```

**⚠️ Atenção:**  
Edite as variáveis no início do script para refletir seus IPs antes de executar!

---

# Licença

MIT License © VIPs-com

---

![CHANGELOG Automation](https://github.com/VIPs-com/proxmox-scripts/actions/workflows/update-changelog.yml/badge.svg)
