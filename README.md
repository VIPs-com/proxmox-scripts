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

---

## 📜 Histórico de Alterações
- 📄 [CHANGELOG.md](CHANGELOG.md) - Histórico completo de mudanças
- 📦 Releases no GitHub: veja versões disponíveis
- ✅ Auto-atualização via GitHub Actions

---

## 📌 `postinstall-aurora-luna.sh`

**Script de pós-instalação e configuração essencial para os nós Aurora e Luna do seu cluster Proxmox VE 8.**

### 🔥 Principais Recursos
- ✔️ Configuração automática de firewall (cluster + VLANs)
- ✔️ Hardening SSH (opcional)
- ✔️ Sincronização NTP
- ✔️ Ajuste de repositórios (ativa `no-subscription`)
- ✔️ Suporte completo às VLANs

| VLAN               | Finalidade                  |
|--------------------|-----------------------------|
| `172.20.220.0/24`  | Rede Principal do Cluster   |
| `172.21.221.0/24`  | Gerenciamento Interno       |
| `172.25.125.0/24`  | Rede Wi-Fi Arkadia          |

---

## 🧩 Pré-requisitos

1. Proxmox VE 8.x instalado nos nós.
2. Acesso **root** via SSH ou WebUI.
3. Conexão com a internet.
4. **Cluster já criado manualmente via WebUI:**

```text
Datacenter > Cluster > Create Cluster (primeiro nó)
Datacenter > Cluster > Join Cluster (nos nós adicionais)
```

Execute o script **apenas após o cluster estar sincronizado e sem erros** no WebUI.

---

## ▶️ Como Executar

### Método 1: `curl` (recomendado)
```bash
curl -sL https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/postinstall-aurora-luna.sh | bash
```

### Método 2: `wget` + execução manual
```bash
wget https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/postinstall-aurora-luna.sh
chmod +x postinstall-aurora-luna.sh
sudo ./postinstall-aurora-luna.sh
```

⚠️ Após a execução em cada nó, **reinicie o sistema** quando for solicitado.

---

## 🧰 Troubleshooting (Resolução de Problemas)

| Erro Comum                         | Solução                                                                 |
|------------------------------------|--------------------------------------------------------------------------|
| Falha no NTP                       | Verifique porta UDP 123 e conectividade externa.                         |
| IP inválido                        | Revise `CLUSTER_PEER_IPS` no script ou no arquivo de config.             |
| Erro no firewall                   | Rode `pve-firewall status` e/ou `journalctl -xeu pve-firewall`.          |
| Falha ao baixar pacotes            | Teste com `ping google.com` e `apt update`.                              |
| Nó não entra no cluster            | Verifique tokens e conectividade. Confirme que o cluster já foi criado.  |

---

## 💡 Como Contribuir

1. Faça um Fork deste repositório.
2. Clone o Fork localmente:
```bash
git clone https://github.com/SEU-USUARIO/proxmox-scripts.git
cd proxmox-scripts
```
3. Crie uma branch:
```bash
git checkout -b feature/nova-funcionalidade
```
4. Faça as alterações e envie:
```bash
git commit -m "✨ Nova funcionalidade X adicionada"
git push origin feature/nova-funcionalidade
```
5. Abra um Pull Request explicando sua contribuição. 🚀

---

## 🌐 Acesso Rápido ao Proxmox WebUI

- 🔹 [Aurora WebUI](https://172.20.220.20:8006)
- 🔹 [Luna WebUI](https://172.20.220.21:8006)

> (Adicione uma captura da interface em `assets/proxmox-interface-example.png` para visualização aqui)

---

## 🧭 Roadmap do Projeto

| Funcionalidade                         | Status         |
|----------------------------------------|----------------|
| Melhorias de segurança no firewall     | ✅ Concluído    |
| Verificações automatizadas             | ✅ Concluído    |
| Integração com Zabbix                  | 🚀 Em andamento|
| Suporte ao Proxmox Backup Server       | 🛠️ Planejado    |

---

## ❓ FAQ

**🔹 Preciso de root para rodar o script?**  
Sim. Ele altera configurações de sistema e firewall.

**🔹 Funciona em versões anteriores ao Proxmox 8?**  
Não oficialmente. O suporte é garantido apenas para 8.x.

**🔹 O script reinicia o sistema?**  
Ele pergunta antes de reiniciar. Você pode adiar se preferir.

---

## 🧪 Benchmark (opcional)

Rode no shell do Proxmox para avaliar o desempenho do seu nó:
```bash
pveperf
```

---

## 📝 Licença

Distribuído sob licença [MIT](LICENSE). Uso livre para fins pessoais e comerciais, com atribuição.
