# 🚀 Scripts Proxmox VE 8 - Cluster Aurora/Luna <img src="assets/proxmox-icon.png" width="30">
![Proxmox Version](https://img.shields.io/badge/Proxmox-8.x-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

## 📚 Documentação
- [CHANGELOG.md](CHANGELOG.md) - Histórico completo de alterações
- ![CHANGELOG Automation](https://github.com/VIPs-com/proxmox-scripts/actions/workflows/update-changelog.yml/badge.svg)

  
### 🔗 Links Rápidos
- [Aurora WebUI](https://172.20.220.20:8006)
- [Luna WebUI](https://172.20.220.21:8006)
- [Documentação Proxmox](https://pve.proxmox.com/wiki/Main_Page)

## 📌 postinstall-aurora-luna.sh
**Script de pós-instalação para nós Aurora (172.20.220.20) e Luna (172.20.220.21)**

### 🔥 Features
- Configuração automática de firewall
- Hardening SSH (opcional)
- Sincronização NTP
- Suporte às VLANs:
  - `172.20.220.0/24` (Cluster)
  - `172.21.221.0/24` (Gerenciamento)
  - `172.25.125.0/24` (Wi-Fi)

### 🚀 Como Executar
```bash
curl -sL https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/proxmox-postinstall-aurora-luna.sh | bash

🧩 Pré-requisitos
Proxmox VE 8.x instalado
Acesso root via SSH/WebUI
Conexão com a internet

‼️ Troubleshooting
Erro	Solução
"Falha no NTP"	Verifique se a porta UDP 123 está aberta no firewall
"IP inválido"	Confira os IPs em /etc/proxmox-postinstall.conf
🤝 Como Contribuir
Faça um fork

Crie um branch: git checkout -b feature/nova-funcao
Commit: git commit -m "Adiciona X"
Push: git push origin feature/nova-funcao
Abra um Pull Request







