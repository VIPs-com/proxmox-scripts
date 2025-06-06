# 🚀 Proxmox Scripts - Cluster Aurora/Luna (v12.2)

![Proxmox Version](https://img.shields.io/badge/Proxmox-8.x-orange)
![Versão](https://img.shields.io/badge/version-12.2-blue)
![Ceph](https://img.shields.io/badge/Ceph-Quincy-red)
![License](https://img.shields.io/badge/license-MIT-blue)
![CHANGELOG Automation](https://github.com/VIPs-com/proxmox-scripts/actions/workflows/update-changelog.yml/badge.svg)

> Scripts automatizados e otimizados para diagnóstico, instalação e hardening de servidores Proxmox VE 8.x no cluster Aurora/Luna.

---

## 📦 Scripts Disponíveis

| Script                                       | Função                                                                 |
|----------------------------------------------|------------------------------------------------------------------------|
| `utils/diagnostico-proxmox.sh`               | Diagnóstico avançado de rede, serviços, discos, ZFS e cluster Proxmox |
| `scripts/proxmox-postinstall-aurora-luna.sh` | Configuração inicial completa do nó                                   |
| `scripts/proxmox-firewall-config.sh`         | Aplica regras de firewall via arquivos `host.fw` e `cluster.fw` com validação segura |

---

## ✅ Execução Rápida via `curl`

**1. Diagnóstico Completo:**
```bash
bash <(curl -s https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/utils/diagnostico-proxmox.sh)
```

**2. Pós-instalação:**
```bash
bash <(curl -s https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/scripts/proxmox-postinstall-aurora-luna.sh)
```

**3. Aplicação de Regras de Firewall:**
```bash
bash <(curl -s https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/scripts/proxmox-firewall-config.sh)
```

> ⚠️ O script de firewall realiza validação de sintaxe e backups automáticos antes de aplicar qualquer regra.

---

## 🛡️ Requisitos Mínimos

Antes de executar, instale:
```bash
apt update && apt install -y curl wget iproute2 dnsutils iputils-ping netcat systemd-timesyncd ntp smartmontools zfsutils-linux
```

---

## 📄 Licença

MIT License © VIPs-com