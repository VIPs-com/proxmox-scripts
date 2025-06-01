# 🚀 Proxmox Scripts - Cluster Aurora/Luna

![Proxmox Version](https://img.shields.io/badge/Proxmox-8.x-orange)
![Version](https://img.shields.io/github/v/release/VIPs-com/proxmox-scripts?include_prereleases)
![CHANGELOG](https://img.shields.io/badge/CHANGELOG-auto--updated-brightgreen)
![License](https://img.shields.io/badge/license-MIT-blue)

> Scripts de automação para servidores **Proxmox VE** no cluster **Aurora/Luna**

---

## 📌 Script de Pós-Instalação

**`postinstall-aurora-luna.sh`** – Configura automaticamente os nós do cluster:

- **Aurora** – `172.20.220.20`  
- **Luna** – `172.20.220.21`

---

### 🔥 Recursos Principais

- 🛡️ Configuração automática de **firewall**
- 🔒 Aplicação de **hardening SSH**
- ⏱ Ativação da **sincronização NTP**
- 🌐 Suporte às **VLANs**:

| VLAN             | Propósito         |
|------------------|-------------------|
| `172.20.220.0/24` | Cluster principal |
| `172.21.221.0/24` | Gerenciamento     |
| `172.25.125.0/24` | Rede Wi-Fi        |

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

- [🌐 Acessar Aurora WebUI](https://172.20.220.20:8006)
- [🌐 Acessar Luna WebUI](https://172.20.220.21:8006)
- [📄 Histórico de alterações (CHANGELOG)](https://github.com/VIPs-com/proxmox-scripts/releases)
- [⚙️ Workflow de automação (GitHub Actions)](https://github.com/VIPs-com/proxmox-scripts/actions)

---

## 🤝 Como Contribuir

```bash
git clone https://github.com/VIPs-com/proxmox-scripts.git
cd proxmox-scripts

git checkout -b minha-feature

# Faça suas melhorias

git commit -m "Minha contribuição"
git push origin minha-feature
```

Depois, abra um **Pull Request** no GitHub!

---

📬 *Sugestões, bugs ou melhorias? Sinta-se à vontade para abrir uma issue ou PR!*
