# 🚀 Scripts Proxmox VE 8 - Cluster Aurora/Luna <img src="assets/proxmox-icon.png" width="30">

![Version](https://img.shields.io/github/v/release/VIPs-com/proxmox-scripts?include_prereleases&style=flat-square)
![CHANGELOG](https://img.shields.io/badge/CHANGELOG-auto--updated-brightgreen?style=flat-square)
![GitHub Actions](https://img.shields.io/github/actions/workflow/status/VIPs-com/proxmox-scripts/update-changelog.yml?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)

---

## 📚 Documentação & Recursos

### 📌 Links Rápidos

- 🔗 [Aurora WebUI](https://172.20.220.20:8006)
- 🔗 [Luna WebUI](https://172.20.220.21:8006)
- 📖 [Documentação Oficial do Proxmox](https://pve.proxmox.com/wiki/Main_Page)

---

## 📌 `postinstall-aurora-luna.sh`

**Script de pós-instalação para os nós Aurora (`172.20.220.20`) e Luna (`172.20.220.21`) do cluster Proxmox VE 8.**

### 🔥 Funcionalidades

- ✅ Configuração automática de firewall
- ✅ Hardening SSH (opcional)
- ✅ Sincronização NTP
- ✅ Gerenciamento de repositórios (`no-subscription`)
- ✅ Suporte a VLANs

| VLAN             | Finalidade                     |
|------------------|--------------------------------|
| `172.20.220.0/24`| Rede Principal do Cluster      |
| `172.21.221.0/24`| Rede de Gerenciamento Interno  |
| `172.25.125.0/24`| Rede Wi-Fi Arkadia             |

---

## 🚀 Como Executar

> ⚠️ Este script **deve ser executado individualmente em cada nó**, **somente após o cluster ter sido criado manualmente pela WebUI**.

### 🧩 Pré-requisitos

1. Proxmox VE 8.x instalado
2. Acesso root via SSH ou Shell
3. Conectividade com a internet
4. Cluster criado manualmente:

**Passos:**

1. Acesse `https://172.20.220.20:8006`
2. Vá em `Datacenter > Cluster > Create Cluster`
3. Nos demais nós, vá em `Join Cluster` com IP/token do nó principal
4. Prossiga com o script após todos os nós estarem sincronizados

### ▶️ Execução via `curl` (recomendado)

```bash
curl -sL https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/postinstall-aurora-luna.sh | bash

📁 Alternativa com wget
wget https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/postinstall-aurora-luna.sh
chmod +x postinstall-aurora-luna.sh
sudo ./postinstall-aurora-luna.sh
🔄 Após a execução, recomenda-se reiniciar o nó para aplicar todas as configurações.

❗ Troubleshooting
Erro Comum	Solução
Falha no NTP	Verifique conectividade e porta UDP 123
IP inválido	Confira variáveis no script ou arquivo /etc/proxmox-postinstall.conf
Erro ao aplicar firewall	Use pve-firewall status ou journalctl -xeu pve-firewall
Erro ao baixar pacotes	Verifique acesso à internet com ping ou apt update
Nó não entra no cluster	Confirme se o cluster foi criado corretamente e os nós se comunicam

🤝 Contribuições
Faça um fork do repositório
Clone para sua máquina local:
git clone https://github.com/SEU-USUARIO/proxmox-scripts.git
cd proxmox-scripts
Crie uma branch:

git checkout -b feature/sua-funcionalidade
Edite, commit e envie:
git commit -m "✨ Nova funcionalidade"
git push origin feature/sua-funcionalidade

Abra um Pull Request no GitHub 🚀

📷 Interface Web Proxmox
Se você tiver um print, salve em assets/proxmox-interface-example.png e adicione aqui:
![Exemplo da Interface](assets/proxmox-interface-example.png)

🗺️ Roadmap
Funcionalidade	Status
Melhorias no firewall	✅ Concluído
Automatização de verificações	✅ Concluído
Integração com Zabbix	🚧 Em andamento
Suporte ao Proxmox Backup Server	🛠️ Planejado

❓ FAQ
Preciso de root para executar?
Sim.

Funciona no Proxmox 7.x ou anterior?
Não garantido.

O script reinicia automaticamente?
Não. Ele pede sua confirmação.

📊 Benchmark
Use o comando abaixo no terminal do Proxmox para verificar desempenho:
pveperf

📝 Licença
Este projeto está sob a licença MIT. Consulte o arquivo LICENSE para detalhes.


---





