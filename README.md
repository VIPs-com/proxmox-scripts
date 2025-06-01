# 🚀 Proxmox Scripts - Cluster Aurora/Luna <img src="assets/proxmox-icon.png" width="30">
![Version](https://img.shields.io/github/v/release/VIPs-com/proxmox-scripts?include_prereleases&style=flat-square)
![CHANGELOG](https://img.shields.io/badge/CHANGELOG-auto--updated-brightgreen?style=flat-square)
![GitHub Actions](https://img.shields.io/github/actions/workflow/status/VIPs-com/proxmox-scripts/update-changelog.yml?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)

---

## 📚 Documentação & Recursos
📌 **Links Rápidos**
- 🔗 [Aurora WebUI](https://172.20.220.20:8006)
- 🔗 [Luna WebUI](https://172.20.220.21:8006)
- 📖 [Documentação Oficial Proxmox](https://pve.proxmox.com/wiki/Main_Page)

📌 **Histórico de Alterações**
- 📜 [CHANGELOG.md](CHANGELOG.md) - Histórico completo de mudanças
- 🔄 ![CHANGELOG Auto-Updated](https://img.shields.io/badge/CHANGELOG-auto--updated-brightgreen)
- 📦 ![GitHub Releases](https://img.shields.io/github/v/release/VIPs-com/proxmox-scripts?include_prereleases)

---

## 📌 postinstall-aurora-luna.sh
**Script de pós-instalação para os nós Aurora (172.20.220.20) e Luna (172.20.220.21)**

### 🔥 Principais Recursos
✔ Configuração automática de firewall  
✔ Hardening SSH (opcional)  
✔ Sincronização NTP  
✔ Suporte às VLANs:

| VLAN                | Finalidade           |
|---------------------|----------------------|
| `172.20.220.0/24`   | Cluster Principal    |
| `172.21.221.0/24`   | Gerenciamento        |
| `172.25.125.0/24`   | Wi-Fi Arkadia        |

---

## 🚀 Como Executar
📌 **Método com `curl`**:
```bash
curl -sL https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/proxmox-postinstall-aurora-luna.sh | bash

📌 Alternativa com wget:
wget https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/proxmox-postinstall-aurora-luna.sh
chmod +x proxmox-postinstall-aurora-luna.sh
sudo ./proxmox-postinstall-aurora-luna.sh



🔄 Troubleshooting (Resolução de Problemas)
| ❌ Erro | 🛠️ Solução | 
| "Falha no NTP" | Verifique se a porta UDP 123 está aberta no firewall | 
| "IP inválido" | Confira os IPs em /etc/proxmox-postinstall.conf | 
| "Falha ao aplicar firewall" | Execute pve-firewall status para verificar logs | 
| "Erro ao baixar pacotes" | Confira se apt update consegue acessar repositórios | 



🤝 Como Contribuir
💡 Quer melhorar este projeto? Faça um fork e envie um PR!
1️⃣ Clone o repositório
git clone https://github.com/VIPs-com/proxmox-scripts.git


2️⃣ Crie uma branch para sua melhoria
git checkout -b minha-feature


3️⃣ Faça suas alterações e envie um commit (use emojis para melhor organização)
git commit -m "✨ Adiciona novo recurso X"
git push origin minha-feature


4️⃣ Abra um Pull Request explicando sua contribuição! 🚀
🔗 Guia Oficial de Contribuição do GitHub

🌐 Proxmox WebUI
🔹 Aurora → WebUI Aurora
🔹 Luna → WebUI Luna
📷 Exemplo da Interface Web:
Proxmox Interface

🚧 Roadmap do Projeto
| 📌 Funcionalidade | Status | 
| Melhorias na segurança do firewall | ✅ Concluído | 
| Automatização de verificações | ✅ Concluído | 
| Integração com monitoramento via Zabbix | 🚀 Em desenvolvimento | 
| Suporte ao Proxmox Backup Server | 🛠️ Planejado | 


📌 FAQ (Perguntas Frequentes)
🔹 Preciso de acesso root para rodar o script?
Sim, todas as configurações exigem privilégios administrativos.
🔹 Esse script suporta versões anteriores do Proxmox?
Ele foi otimizado para Proxmox VE 8.x, então algumas funções podem não funcionar corretamente em versões mais antigas.
🔹 O script faz reboot automático?
Ele pede confirmação antes de reiniciar. Você pode adiar manualmente se precisar.

🎯 Benchmark / Testes de Performance
🔹 Após a instalação, o desempenho do cluster pode ser medido com:
pveperf


Esse comando fornece métricas detalhadas sobre disco, CPU e RAM, permitindo validação de melhorias no sistema.

📝 Licença
Este projeto está sob a licença MIT. Para mais informações, consulte o arquivo LICENSE.

---
