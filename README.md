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
- 📖 [Documentação Oficial Proxmox](https://pve.proxmox.com/wiki/Main_Page)

### 📌 Histórico de Alterações
- 📜 [CHANGELOG.md](CHANGELOG.md) - Histórico completo de mudanças
- 🔄 ![CHANGELOG Auto-Updated](https://img.shields.io/badge/CHANGELOG-auto--updated-brightgreen)
- 📦 ![GitHub Releases](https://img.shields.io/github/v/release/VIPs-com/proxmox-scripts?include_prereleases)

---

## 📌 `postinstall-aurora-luna.sh`

**Script de pós-instalação e configuração essencial para os nós Aurora (172.20.220.20) e Luna (172.20.220.21) do seu cluster Proxmox VE 8.**

### 🔥 Principais Recursos
- ✔ **Configuração automática de firewall:** Regras otimizadas para comunicação do cluster e segurança.
- ✔ **Hardening SSH (opcional):** Aumenta a segurança do acesso SSH, desativando o login de root por senha.
- ✔ **Sincronização NTP:** Garante que o tempo dos nós esteja sempre preciso para o bom funcionamento do cluster.
- ✔ **Gerenciamento de repositórios:** Desabilita o repositório de assinatura e ativa o repositório `no-subscription`.
- ✔ **Suporte às VLANs:** Configuração de regras de firewall e `localnet` para as VLANs do seu ambiente.

| VLAN | Finalidade |
|---|---|
| `172.20.220.0/24` | Rede Principal do Cluster (Home Lab) |
| `172.21.221.0/24` | Rede de Gerenciamento Interno |
| `172.25.125.0/24` | Rede Wi-Fi Arkadia |

---

## 🚀 Como Executar

Este script **DEVE SER EXECUTADO INDIVIDUALMENTE EM CADA NÓ** e **APÓS A CRIAÇÃO MANUAL DO CLUSTER VIA WEBUI**.

### 🧩 **Pré-requisitos Cruciais:**
1.  **Proxmox VE 8.x** instalado em todos os nós.
2.  **Acesso root** via SSH ou WebUI Shell.
3.  **Conexão com a internet** para download de pacotes e atualizações.
4.  **CLUSTER CRIADO MANUALMENTE VIA WEBUI (Passo OBRIGATÓRIO ANTES DO SCRIPT):**
    * Acesse o WebUI do **primeiro nó** (ex: `https://172.20.220.20:8006`).
    * Vá em **`Datacenter > Cluster > Create Cluster`** e defina um nome para seu cluster.
    * Para **cada nó adicional**, acesse seu WebUI (ex: `https://172.20.220.21:8006`).
    * Vá em **`Datacenter > Cluster > Join Cluster`** e utilize o IP do primeiro nó e o token para adicionar.
    * **Prossiga com a execução do script SOMENTE após o cluster estar totalmente funcional e sincronizado (todos os nós visíveis e sem erros no WebUI).**

### ▶️ **Execução do Script:**

**Método com `curl` (Recomendado):**
Execute este comando no Shell de cada nó Proxmox:
```bash
curl -sL [https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/postinstall-aurora-luna.sh](https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/postinstall-aurora-luna.sh) | bash

Método Alternativo com wget:
Baixe o script e execute-o localmente em cada nó:

Bash

wget [https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/postinstall-aurora-luna.sh](https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/postinstall-aurora-luna.sh)
chmod +x postinstall-aurora-luna.sh
sudo ./postinstall-aurora-luna.sh
⚠️ Lembrete: Após a execução do script em cada nó, um reboot é altamente recomendado para aplicar todas as configurações (o script perguntará se você deseja reiniciar).

🔄 Troubleshooting (Resolução de Problemas)
❌ Erro Comum	🛠️ Solução Sugerida
"Falha no NTP"	Verifique se a porta UDP 123 (NTP) está aberta no firewall e se há conectividade externa (ex: ping google.com).
"IP inválido"	Confira os IPs definidos em CLUSTER_PEER_IPS no script ou no arquivo /etc/proxmox-postinstall.conf se você o estiver utilizando.
"Falha ao aplicar firewall"	Execute pve-firewall status ou journalctl -xeu pve-firewall para verificar logs e erros específicos do serviço de firewall.
"Erro ao baixar pacotes"	Verifique a conectividade com a internet (ping ftp.debian.org) e se o comando apt update consegue acessar os repositórios.
"Nó não consegue se juntar ao cluster"	Verifique o Passo 4 dos Pré-requisitos: O cluster deve ser criado manualmente antes de rodar o script. Verifique também o status do firewall (pve-firewall status) e a conectividade entre os nós (ping, nc -zv IP PORTA).

Exportar para as Planilhas
🤝 Como Contribuir
💡 Quer melhorar este projeto? Sua contribuição é bem-vinda!

Faça um Fork deste repositório para sua conta GitHub.
Clone o repositório para sua máquina local:
Bash

git clone [https://github.com/SEU-USUARIO/proxmox-scripts.git](https://github.com/SEU-USUARIO/proxmox-scripts.git)
Crie uma branch para sua melhoria ou correção:
Bash

git checkout -b feature/minha-nova-funcao
Faça suas alterações no código.
Envie um commit com uma mensagem clara e descritiva (use emojis para melhor organização):
Bash

git commit -m "✨ Adiciona novo recurso X"
Faça o Push da sua branch para o seu fork no GitHub:
Bash

git push origin feature/minha-nova-funcao
Abra um Pull Request no repositório original, explicando detalhadamente sua contribuição! 🚀
🔗 Para mais informações sobre como contribuir no GitHub, consulte o Guia Oficial de Contribuição do GitHub.

🌐 Proxmox WebUI - Acesso Rápido
Clique para acessar a interface web de cada nó:

🔹 Aurora WebUI
🔹 Luna WebUI
📷 Exemplo da Interface Web:(Se você tiver uma imagem da sua interface Proxmox, salve-a em assets/proxmox-interface-example.png no seu repositório para que ela apareça aqui)

🚧 Roadmap do Projeto
Confira o que está em desenvolvimento ou planejado para o futuro deste projeto:

📌 Funcionalidade	Status
Melhorias na segurança do firewall	✅ Concluído
Automatização de verificações	✅ Concluído
Integração com monitoramento via Zabbix	🚀 Em desenvolvimento
Suporte ao Proxmox Backup Server	🛠️ Planejado

Exportar para as Planilhas
📌 FAQ (Perguntas Frequentes)
🔹 Preciso de acesso root para rodar o script?
Sim, o script realiza configurações de sistema que exigem privilégios administrativos (usuário root).

🔹 Esse script suporta versões anteriores do Proxmox?
Este script foi otimizado e testado especificamente para Proxmox VE 8.x. Embora algumas partes possam funcionar em versões anteriores, o comportamento ideal não é garantido e podem ocorrer erros.

🔹 O script faz reboot automático?
Não, o script pede confirmação antes de iniciar o processo de reinicialização do nó. Você tem a opção de adiar o reboot e fazê-lo manualmente mais tarde, se necessário.

🎯 Benchmark / Testes de Performance
Para verificar o desempenho do seu nó Proxmox após a instalação e configuração, você pode usar o comando pveperf diretamente no Shell:

Bash

pveperf
Este comando fornece métricas detalhadas sobre o desempenho do disco, uso da CPU e RAM, permitindo que você valide as melhorias no sistema.

📝 Licença
Este projeto é de código aberto e está sob a licença MIT. Para mais informações sobre os termos de uso e distribuição, consulte o arquivo LICENSE no repositório.
