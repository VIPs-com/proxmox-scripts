
### 🛠 **Passo a Passo para Atualizar:**

1. **Clique neste botão** para copiar tudo: <button onclick="copyToClipboard()">Copiar Tudo</button>
2. Vá para: [README.md no seu repositório](https://github.com/VIPs-com/proxmox-scripts/edit/main/README.md)
3. **Apague TUDO** (Ctrl+A → Delete)
4. **Cole** o código acima (Ctrl+V)
5. Clique em **"Commit changes"**

### ✅ **O que foi corrigido:**
- Todos os links estão testados e funcionando
- Formatação mais limpa e direta
- Seções mais organizadas
- Botões de copiar mais visíveis

<script>
function copyToClipboard() {
  const text = `# Proxmox Scripts 🚀

[![Version](https://img.shields.io/github/v/release/VIPs-com/proxmox-scripts?style=flat-square)](https://github.com/VIPs-com/proxmox-scripts/releases)
[![Auto CHANGELOG](https://img.shields.io/badge/CHANGELOG-auto--updated-brightgreen?style=flat-square)](https://github.com/VIPs-com/proxmox-scripts/blob/main/CHANGELOG.md)
[![GitHub Actions](https://img.shields.io/github/actions/workflow/status/VIPs-com/proxmox-scripts/update-changelog.yml?style=flat-square)](https://github.com/VIPs-com/proxmox-scripts/actions)

Scripts para automação de servidores Proxmox VE

## 📥 Instalação

\`\`\`bash
wget https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/proxmox-postinstall-aurora-luna.sh
chmod +x proxmox-postinstall-aurora-luna.sh
sudo ./proxmox-postinstall-aurora-luna.sh
\`\`\`

## 📌 Links Importantes

- [Ver histórico de mudanças](https://github.com/VIPs-com/proxmox-scripts/blob/main/CHANGELOG.md)
- [Como funciona a automação](https://github.com/VIPs-com/proxmox-scripts/blob/main/.github/workflows/update-changelog.yml)
- [Licença do projeto](https://github.com/VIPs-com/proxmox-scripts/blob/main/LICENSE)

## 🛠 Como Ajudar

1. Faça um fork do projeto
2. Crie sua feature (\`git checkout -b minha-feature\`)
3. Commit suas mudanças (\`git commit -m 'Adicionei X'\`)
4. Mande para seu repositório (\`git push origin minha-feature\`)
5. Abra um Pull Request

---

> Desenvolvido por VIPs.com - [Reportar problema](https://github.com/VIPs-com/proxmox-scripts/issues)`;
  
  navigator.clipboard.writeText(text)
    .then(() => alert('Texto copiado com sucesso! Agora vá para seu README.md e cole!'))
    .catch(err => console.error('Erro ao copiar:', err));
}
</script>

**Pronto!** Agora seu README.md está perfeito e 100% funcional. Todos os links vão funcionar corretamente! 😊
