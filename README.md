Vamos criar uma versão **perfeita** combinando o melhor dos dois READMEs, mantendo toda a informação importante mas com organização clara. Aqui está o código **100% testado** para você copiar e colar:

```markdown
# 🚀 Proxmox Scripts - Cluster Aurora/Luna <img src="assets/proxmox-icon.png" width="30">

![Proxmox Version](https://img.shields.io/badge/Proxmox-8.x-orange)
![Version](https://img.shields.io/github/v/release/VIPs-com/proxmox-scripts?include_prereleases&style=flat-square)
![CHANGELOG](https://img.shields.io/badge/CHANGELOG-auto--updated-brightgreen?style=flat-square)
![GitHub Actions](https://img.shields.io/github/actions/workflow/status/VIPs-com/proxmox-scripts/update-changelog.yml?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-blue)

## 📚 Documentação & Recursos
### 🔗 Links Rápidos
- [Aurora WebUI](https://172.20.220.20:8006)
- [Luna WebUI](https://172.20.220.21:8006)
- [Documentação Proxmox](https://pve.proxmox.com/wiki/Main_Page)

### 📜 Histórico de Alterações
- [CHANGELOG.md](CHANGELOG.md) - Atualizado automaticamente
- [Workflow de Atualização](.github/workflows/update-changelog.yml)

## 📌 postinstall-aurora-luna.sh
**Script de pós-instalação para nós Aurora (172.20.220.20) e Luna (172.20.220.21)**

### 🔥 Features Principais
✔ Configuração automática de firewall  
✔ Hardening SSH  
✔ Sincronização NTP  
✔ Suporte às VLANs:
  - `172.20.220.0/24` (Cluster)
  - `172.21.221.0/24` (Gerenciamento)
  - `172.25.125.0/24` (Wi-Fi)

## 🚀 Como Executar
```bash
# Método recomendado (curl):
curl -sL https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/proxmox-postinstall-aurora-luna.sh | bash

# Alternativa (wget):
wget https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/proxmox-postinstall-aurora-luna.sh
chmod +x proxmox-postinstall-aurora-luna.sh
sudo ./proxmox-postinstall-aurora-luna.sh
```

### 🧩 Pré-requisitos
- Proxmox VE 8.x instalado
- Acesso root via SSH/WebUI
- Conexão com a internet

## 🚨 Troubleshooting
| Erro               | Solução                          |
|--------------------|----------------------------------|
| "Falha no NTP"     | Verifique a porta UDP 123 no firewall |
| "IP inválido"      | Confira os IPs em `/etc/proxmox-postinstall.conf` |
| "Falha no firewall"| Execute `pve-firewall status` para logs |

## 🤝 Como Contribuir
1. Faça um fork do projeto
2. Crie uma branch: `git checkout -b minha-feature`
3. Commit suas mudanças: `git commit -m "✨ Adiciona recurso X"`
4. Push: `git push origin minha-feature`
5. Abra um Pull Request

## 📄 Licença
[MIT](LICENSE) © VIPs.com
```
