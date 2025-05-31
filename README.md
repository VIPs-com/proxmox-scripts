# proxmox-scripts
"Scripts de automação para cluster Proxmox Aurora/Luna"

# 📜 Scripts Proxmox VE 8 - Cluster Aurora/Luna

## postinstall-aurora-luna.sh
Script de pós-instalação para nós **Aurora (172.20.220.20)** e **Luna (172.20.220.21)**

### Como Executar:
```bash
curl -sL https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/proxmox-postinstall-aurora-luna.sh | bash
```

### Funcionalidades:
- 🔥 Configura firewall automático
- ⚡ Hardening SSH (opcional)
- 🕒 Sincronização NTP
- 📡 Regras para VLANs 172.20.220.0/24, 172.21.221.0/24 e 172.25.125.0/24

![Diagrama do Cluster](https://exemplo.com/imagem-cluster.png) *(opcional)*
