# Disk Watchdog

Monitor leve de uso de disco em `/` que envia alertas para um servidor **Discord** antes de chegar em 100%, com integração via `systemd` (service + timer). Toda configuração sensível vem de um arquivo local seguro (`/etc/disk-watchdog/env.conf`); **nada de secrets no repositório**.

## Visão geral

O script (`disk-watchdog.sh`) checa o uso da partição raiz e, quando ultrapassa o limiar definido, dispara um alerta único via webhook do Discord. Ele mantém um flag para evitar spam enquanto o uso permanece alto e reseta o estado quando o disco libera espaço.

## Pré-requisitos

- Linux com `systemd`
- `bash`
- `curl`
- Permissões de root/sudo para colocar arquivos em `/usr/local/bin` e `/etc`, e para habilitar unidades systemd

## Instalação no servidor (via `setup.sh`)

O jeito mais simples e seguro de instalar / atualizar é usar o `setup.sh`, que:

- Baixa/atualiza o script e as unidades systemd.
- Cria ou reconfigura o arquivo seguro `/etc/disk-watchdog/env.conf` (com webhook, thresholds e nome do servidor).
- Habilita e inicia o timer.

### 1. Baixar o `setup.sh` e torná-lo executável

```bash
curl -fsSL https://raw.githubusercontent.com/rafaell1995/disk-watchdog/main/setup.sh -o setup.sh
chmod +x setup.sh
```

### 2. Rodar para instalação inicial

```bash
sudo ./setup.sh
```

Ele vai:

- Baixar/atualizar `disk-watchdog.sh`, `disk-watchdog.service` e `disk-watchdog.timer`.
- Pedir interativamente o webhook do Discord, threshold, margem de recuperação e nome do servidor.
- Criar `/etc/disk-watchdog/env.conf` com permissões seguras.
- Habilitar e iniciar o timer.

### 3. Modos/flags úteis (reexecução segura)

- `--update-scripts`
  Atualiza apenas o script e as unidades systemd, **sem** tocar em `env.conf`:

  ```bash
  sudo ./setup.sh --update-scripts
  ```

- `--reconfigure`
  Reconfigura interativamente **somente** o arquivo `env.conf` (faz backup do anterior):

  ```bash
  sudo ./setup.sh --reconfigure
  ```

- `--force`
  Atualiza tudo e força reconfiguração do `env.conf` (equivalente a `--update-scripts --reconfigure`):

  ```bash
  sudo ./setup.sh --force
  ```

### 4. Verificação

```bash
# Verificar o status do timer
sudo systemctl status disk-watchdog.timer

# Ver logs da última execução
sudo journalctl -u disk-watchdog.service

# Ver log customizado
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
