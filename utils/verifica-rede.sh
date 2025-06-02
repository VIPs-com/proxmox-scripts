# 🔍 Script de Verificação de Rede - Proxmox VE

**Arquivo:** `utils/verifica-rede.sh`  
**Propósito:** Diagnosticar e validar a conectividade entre nós de um cluster **antes** da execução do script de pós-instalação (`post-install.sh`).

---
#!/bin/bash

# Verifica/Instala curl (se não existir)
if ! command -v curl &> /dev/null; then
    echo "ℹ️  Instalando curl..."
    apt-get update && apt-get install -y curl || {
        echo "❌ Falha ao instalar curl"
        exit 1
    }
fi

# Restante do script...
---

## 📌 Funcionalidades

✅ **Teste de latência (ping):** Mede o tempo de resposta entre os nós.  
🔌 **Verificação de portas essenciais:** Garante que as portas usadas pelo Proxmox e Corosync estão acessíveis.  
🌐 **Resolução DNS reversa:** Verifica se os IPs têm nome reverso válido (útil para clustering).  
📶 **Detecção de IP local:** Mostra o IP atual do nó que está rodando o teste.  
🛑 **Retorno com status de erro:** O script retorna `exit 1` em caso de falhas detectadas, útil para automações.  
🔇 **Modo silencioso (`-s` ou `--silent`):** Oculta mensagens informativas, exibindo apenas erros.  
♻️ **Parâmetros via variáveis de ambiente:** Defina `CLUSTER_IPS` e/ou `PORTS` para testar IPs ou portas diferentes.

---

## 📥 Como Usar

### 1. Execução rápida via `curl`:
```bash
bash <(curl -s https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/utils/verifica-rede.sh)
```

### 2. Ou baixe e execute localmente:
```bash
mkdir -p utils
wget -O utils/verifica-rede.sh https://raw.githubusercontent.com/VIPs-com/proxmox-scripts/main/utils/verifica-rede.sh
chmod +x utils/verifica-rede.sh
./utils/verifica-rede.sh
```

### 3. Exemplo de uso com variáveis de ambiente:
```bash
CLUSTER_IPS="10.0.0.1,10.0.0.2" PORTS="22,8006,5404" ./utils/verifica-rede.sh -s
```

---

## 🧪 Exemplo de saída esperada

```plaintext
ℹ️  🔍 Diagnóstico de Rede - Sun Jun  1 14:00:00 UTC 2025
ℹ️  IP local: 172.20.220.10
----------------------------------------
ℹ️  1/3 - Medição de Latência:
✅  172.20.220.20 → Latência média: 0.312ms
✅  172.20.220.21 → Latência média: 0.290ms

ℹ️  2/3 - Verificando portas essenciais:
ℹ️  🔧 Nó 172.20.220.20:
✅  Porta 22 → Acessível
✅  Porta 8006 → Acessível
✅  Porta 5404 → Acessível
...

ℹ️  3/3 - Verificando resolução DNS:
✅  172.20.220.20 → node-a.lab.local
✅  172.20.220.21 → node-b.lab.local

📊 Resultado Final:
✅ Todos os testes básicos passaram!
ℹ️  Recomendação: Prossiga com a instalação
----------------------------------------
```

---

## ⚠️ Requisitos

Este script depende dos seguintes comandos:
- `ping`
- `dig`
- `timeout`
- `bash` (v4 ou superior)

Se algum deles estiver ausente, o script irá avisar e interromper a execução.

---

## 📁 Localização sugerida no Repositório

Este arquivo e o script devem estar em:
```
proxmox-scripts/
├
└── utils/
    ├── verifica-rede.sh
   
```

---

## ✅ Recomendações

1. Execute esse script **em todos os nós** antes de iniciar a configuração do cluster.
2. Certifique-se de que todos os IPs estejam com portas e DNS funcionando corretamente.
3. Em caso de erro, **não continue** a instalação. Corrija os problemas primeiro.

---

Feito com ❤️ por [VIPs.com](https://github.com/VIPs-com)
