# 🚀 Proxmox Scripts - Cluster Aurora/Luna (v12.1)

![Proxmox Version](https://img.shields.io/badge/Proxmox-8.x-orange)
![Versão](https://img.shields.io/badge/version-12.1-blue)
![Ceph](https://img.shields.io/badge/Ceph-Quincy-red)
![License](https://img.shields.io/badge/license-MIT-blue)
![CHANGELOG Automation](https://github.com/VIPs-com/proxmox-scripts/actions/workflows/update-changelog.yml/badge.svg)

> Scripts automatizados e otimizados para instalação, configuração e hardening de servidores Proxmox VE 8.x no cluster Aurora/Luna, com foco em redes seguras, Ceph no-subscription, sincronização de tempo robusta e firewall por arquivos.

---

## 📦 Scripts Principais

| Script                          | Função                                                                 |
|--------------------------------|-------------------------------------------------------------------------|
| `verifica-rede.sh`             | Diagnóstico pré-execução: latência, portas, DNS, MTU, serviços, NTP e cluster |
| `proxmox-postinstall-aurora-luna.sh` | Configuração completa do nó: repositórios, timezone, firewall, hardening etc. |

---

## ⚙️ Requisitos Mínimos

Antes de executar qualquer script, assegure-se de que seu sistema atenda aos seguintes requisitos:

### ✅ Dependências obrigatórias (instale com apt):
```bash
apt update && apt install -y curl wget iproute2 dnsutils iputils-ping netcat systemd-timesyncd ntp
```

- `curl`, `wget` - Download dos scripts
- `ping`, `ip`, `ss`, `netcat` - Testes de rede
- `systemd-timesyncd`, `ntp` - Sincronização de tempo
- `dnsutils` - Resolução DNS (dig)

> ⚠️ O script `verifica-rede.sh` verifica todas essas dependências automaticamente.

---

## 📋 Etapas Recomendadas

1. **Diagnóstico prévio** *(antes do postinstall)*:
```bash
curl -sL https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/utils/verifica-rede.sh | bash
```

2. **Executar o script de pós-instalação**:
```bash
curl -sL https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/scripts/proxmox-postinstall-aurora-luna.sh | bash
```

> ⚠️ Execute **em cada nó individualmente** (Aurora, Luna, etc.) via WebUI ou SSH.

---

## 🔥 Novidades da Versão 12.1

- 📡 Verificação e instalação automática do `systemd-timesyncd`
- 🧠 Firewall agora gerenciado via arquivos `host.fw` e `cluster.fw`
- 📦 Remoção do repositório **Ceph Enterprise** e adição do repositório correto **Ceph Quincy no-subscription**
- 🛠 Backup automático dos arquivos editados (`/etc/hosts`, `sources.list`, etc.)
- 🔐 Hardening interativo do SSH (desativa login por senha se desejado)
- 🧹 Limpeza de logs antigos e pacotes residuais

---

## 🌐 VLANs Utilizadas

| VLAN             | Propósito                      |
|------------------|-------------------------------|
| `172.20.220.0/24`| Cluster principal             |
| `172.21.221.0/24`| Rede de gerenciamento         |
| `172.25.125.0/24`| Wi-Fi da infraestrutura Arkadia|

---

## 🧰 Boas Práticas Antes de Executar

### 1. Garanta que os repositórios estejam limpos:
```bash
mv /etc/apt/sources.list.d/ceph.list /etc/apt/sources.list.d/ceph.list.bak
apt update
```

### 2. Adicione o repositório correto do Ceph:
```bash
echo "deb http://download.proxmox.com/debian/ceph-quincy bookworm main" > /etc/apt/sources.list.d/ceph.list
apt update
```

### 3. Certifique-se de que `systemd-timesyncd` está ativo:
```bash
apt install systemd-timesyncd -y
systemctl enable --now systemd-timesyncd
systemctl restart systemd-timesyncd
systemctl status systemd-timesyncd
```

### 4. Diagnostique sua rede com:
```bash
bash <(curl -s https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/utils/verifica-rede.sh)
```

---

## 📚 Documentação Extra

- [Histórico de versões](https://github.com/VIPs-com/proxmox-scripts/releases)
- [Workflow de automação](https://github.com/VIPs-com/proxmox-scripts/actions)
- [ADAPTATION_GUIDE](./ADAPTATION_GUIDE.md)

---

## 🤝 Como Contribuir
```bash
git clone https://github.com/VIPs-com/proxmox-scripts.git
cd proxmox-scripts
git checkout -b minha-contribuicao
# Faça as alterações...
git commit -m "Melhoria X aplicada"
git push origin minha-contribuicao
```

---

## ❓ FAQ Rápido

### "Erro: Ceph enterprise expirado"
> Provavelmente está usando o repositório errado. Veja a seção "Boas Práticas" acima.

### "Erro: systemd-timesyncd não encontrado"
> Instale manualmente com `apt install systemd-timesyncd -y`

### "Portas bloqueadas entre nós"
> Verifique firewall local e certifique-se de que 5404-5405/UDP e 2224/TCP estão abertos entre os nós.

---

## 📄 Licença

MIT License © VIPs-com
