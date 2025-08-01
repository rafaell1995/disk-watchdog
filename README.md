# Disk Watchdog

Monitor leve de uso de disco em `/` que envia alertas para um servidor **Discord** antes de chegar em 100%, com integração via `systemd` (service + timer). Toda configuração sensível vem de um arquivo local seguro (`/etc/disk-watchdog/env.conf`); **nada de secrets no repositório**.

## Visão geral

O script (`disk-watchdog.sh`) checa o uso da partição raiz e, quando ultrapassa o limiar definido, dispara um alerta único via webhook do Discord. Ele mantém um flag para evitar spam enquanto o uso permanece alto e reseta o estado quando o disco libera espaço.

## Pré-requisitos

- Linux com `systemd`
- `bash`
- `curl`
- Permissões de root/sudo para colocar arquivos em `/usr/local/bin` e `/etc`, e para habilitar unidades systemd

## Instalação no servidor

### 1. Copiar os arquivos para os locais corretos

Substitua `SEU_USUARIO`/`nome-do-repo` se for diferente; os exemplos abaixo assumem que os arquivos estão em `https://github.com/rafaell1995/disk-watchdog`:

```bash
# Script principal
sudo curl -fsSL https://raw.githubusercontent.com/rafaell1995/disk-watchdog/main/disk-watchdog.sh -o /usr/local/bin/disk-watchdog.sh
```

```bash
# Unidades systemd
sudo curl -fsSL https://raw.githubusercontent.com/rafaell1995/disk-watchdog/main/disk-watchdog.service -o /etc/systemd/system/disk-watchdog.service
sudo curl -fsSL https://raw.githubusercontent.com/rafaell1995/disk-watchdog/main/disk-watchdog.timer -o /etc/systemd/system/disk-watchdog.timer
```

Ou, se preferir wget:

```bash
sudo wget -qO /usr/local/bin/disk-watchdog.sh https://raw.githubusercontent.com/rafaell1995/disk-watchdog/main/disk-watchdog.sh
sudo wget -qO /etc/systemd/system/disk-watchdog.service https://raw.githubusercontent.com/rafaell1995/disk-watchdog/main/disk-watchdog.service
sudo wget -qO /etc/systemd/system/disk-watchdog.timer https://raw.githubusercontent.com/rafaell1995/disk-watchdog/main/disk-watchdog.timer
```

### 2. Preparar o script

```bash
sudo chmod +x /usr/local/bin/disk-watchdog.sh
sudo chmod 755 /usr/local/bin/disk-watchdog.sh
```

### 3. Criar o arquivo de configuração seguro (`/etc/disk-watchdog/env.conf`)

O serviço lê variáveis de ambiente daquele arquivo. Ele deve conter pelo menos:

- `DISCORD_WEBHOOK_URL`: a URL do webhook do Discord.
- `THRESHOLD`: percentual de uso que aciona o alerta (padrão 85).
- `RECOVER_MARGIN`: quanto precisa cair abaixo do threshold para resetar o alerta (padrão 5).

#### Opção interativa (recomendado):

```bash
read -rp "Discord webhook URL: " webhook
read -rp "Threshold de alerta (em %, padrão 85): " threshold
read -rp "Margem de recuperação (em %, padrão 5): " margin

sudo mkdir -p /etc/disk-watchdog
sudo bash -c "cat <<EOF > /etc/disk-watchdog/env.conf
DISCORD_WEBHOOK_URL=\"$webhook\"
THRESHOLD=${threshold:-85}
RECOVER_MARGIN=${margin:-5}
EOF"

sudo chmod 600 /etc/disk-watchdog/env.conf
```

#### Ou criando manualmente (substitua pelos valores desejados):

```bash
sudo mkdir -p /etc/disk-watchdog
sudo tee /etc/disk-watchdog/env.conf >/dev/null <<EOF
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/SEU_WEBHOOK_ID/SEU_TOKEN"
THRESHOLD=85
RECOVER_MARGIN=5
EOF

sudo chmod 600 /etc/disk-watchdog/env.conf
```

> ⚠️ **Importante:** Esse arquivo contém o webhook; mantenha permissões restritas (`600`) e **não** o versiona. Ele vive em `/etc/disk-watchdog/env.conf`.

### 4. Habilitar e iniciar via systemd

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now disk-watchdog.timer
```

### 5. Verificação

- Ver status do timer:

  ```bash
  sudo systemctl status disk-watchdog.timer
  ```

- Logs da execução:

  ```bash
  sudo journalctl -u disk-watchdog.service
  ```

- Log customizado do script:

  ```bash
  sudo tail -f /var/log/disk-watchdog.log
  ```

## Criando o webhook no Discord

1. No servidor Discord, vá no canal desejado.
2. Clique em **Editar canal** → **Integrações** → **Webhooks** → \*\* Novo webhook\*\*.
3. Copie a URL do webhook e use no passo de criação de `/etc/disk-watchdog/env.conf`.

## Testando manualmente

Para forçar um alerta sem encher o disco, use um threshold temporariamente baixo:

```bash
export THRESHOLD=1
sudo /usr/local/bin/disk-watchdog.sh
```

Verifique:

- Se o flagfile foi criado: `/var/run/disk_watchdog_alerted`
- Se a mensagem chegou no Discord
- Se o log em `/var/log/disk-watchdog.log` registrou a execução

Depois, remova o override do threshold.

## Comportamentos opcionais

Você pode estender o script para, em uso crítico (ex: ≥95%), executar limpezas conservadoras como:

```bash
docker image prune -f --filter "until=72h"
docker builder prune -f --filter "keep-storage=500MB"
```

> **Não automatize** `docker system prune -a` sem revisão, pois pode afetar containers em produção.

## Boas práticas

- Mantenha o webhook do Discord fora do versionamento.
- Use deploy automatizado (Ansible, etc.) para replicar em múltiplas máquinas.
- Monitore o próprio watchdog via `journalctl` e considere canais redundantes se o Discord falhar.

## Contribuindo

1. Faça um fork.
2. Crie uma branch: `git checkout -b minha-melhoria`
3. Faça commits claros.
4. Abra um pull request explicando a mudança.
