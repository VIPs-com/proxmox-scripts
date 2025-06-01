```markdown
# Proxmox Scripts 🚀

![Version](https://img.shields.io/github/v/release/VIPs-com/proxmox-scripts?include_prereleases&style=flat-square)
![CHANGELOG](https://img.shields.io/badge/CHANGELOG-auto--updated-brightgreen?style=flat-square)
![GitHub Actions](https://img.shields.io/github/actions/workflow/status/VIPs-com/proxmox-scripts/update-changelog.yml?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)

> Coleção de scripts para automação e administração de servidores Proxmox VE

## ✨ Features

- Instalação automatizada de pacotes essenciais
- Configuração otimizada para desempenho
- Atualização automática do CHANGELOG
- Sistema de versionamento integrado

## 📦 Instalação Rápida

```bash
wget https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/proxmox-postinstall-aurora-luna.sh
chmod +x proxmox-postinstall-aurora-luna.sh
sudo ./proxmox-postinstall-aurora-luna.sh
```

## 🛠 Como Usar

1. Execute o script como root ou com `sudo`
2. Siga as instruções interativas
3. Revise as alterações no [CHANGELOG.md](CHANGELOG.md)

## 📜 Histórico de Alterações

O CHANGELOG.md é atualizado automaticamente via GitHub Actions:  
🔍 [Ver histórico completo](CHANGELOG.md) | ⚙️ [Workflow](.github/workflows/update-changelog.yml)

## 🤝 Como Contribuir

```bash
# 1. Faça um fork
# 2. Clone seu fork
git clone https://github.com/SEU-USER/proxmox-scripts.git

# 3. Crie um branch
git checkout -b minha-feature

# 4. Commit suas mudanças
git commit -m "Adiciona novo recurso"

# 5. Push
git push origin minha-feature
```

Depois abra um Pull Request explicando sua contribuição!

## 🚨 Troubleshooting

| Problema              | Solução                     |
|-----------------------|-----------------------------|
| Erro de permissão     | Execute com `sudo`          |
| Falha na conexão      | Verifique sua rede          |
| Pacote não encontrado | Atualize os repositórios    |

## 📄 Licença

Distribuído sob licença MIT. Veja o arquivo [LICENSE](LICENSE) para detalhes.
```

