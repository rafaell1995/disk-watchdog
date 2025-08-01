#!/bin/bash

# fallback: carrega o env.conf se existir (útil para execução manual, além do systemd)
ENV_CONF_FILE="/etc/disk-watchdog/env.conf"
if [[ -f "$ENV_CONF_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_CONF_FILE"
fi

# Configurações via variáveis de ambiente (com fallback)
THRESHOLD=${THRESHOLD:-85}
RECOVER_MARGIN=${RECOVER_MARGIN:-5}
DISCORD_WEBHOOK_URL=${DISCORD_WEBHOOK_URL:-}
FLAGFILE=${FLAGFILE:-/var/run/disk_watchdog_alerted}
LOGFILE=${LOGFILE:-/var/log/disk-watchdog.log}

# Identificação do servidor
# SERVER_NAME pode ser definido; se não, usa hostname
if [[ -n "${SERVER_NAME:-}" ]]; then
  SERVER_DISPLAY="$SERVER_NAME"
else
  # tenta FQDN, se falhar usa hostname simples
  SERVER_DISPLAY=$(hostname -f 2>/dev/null || hostname)
fi

timestamp() { date "+%F %T"; }

# Pega uso da partição raiz (/), em %
USAGE=$(df -P / | awk 'NR==2 {gsub(/%/,""); print $5}')

# Envia alerta para Discord (se configurado)
send_alert() {
    local msg="$1"
    echo "$(timestamp): $msg" >> "$LOGFILE"

    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
        # compõe mensagem com identificação
        payload=$(printf '{"content":"⚠️ **Alerta de disco em %s:** %s"}' "$SERVER_DISPLAY" "$msg")
        curl -s -X POST -H "Content-Type: application/json" --data "$payload" "$DISCORD_WEBHOOK_URL" >/dev/null 2>&1
    else
        echo "$(timestamp): Discord webhook não configurado; pulando envio." >> "$LOGFILE"
    fi
}

# Lógica de disparo
if (( USAGE >= THRESHOLD )); then
    if [[ ! -f "$FLAGFILE" ]]; then
        send_alert "Uso da partição / está em ${USAGE}%. Libere espaço antes de atingir 100%."
        touch "$FLAGFILE"
    else
        echo "$(timestamp): já alertado (uso ${USAGE}%)." >> "$LOGFILE"
    fi
else
    # se caiu abaixo do limiar de recuperação, reseta o estado de alerta
    if (( USAGE < THRESHOLD - RECOVER_MARGIN )); then
        [[ -f "$FLAGFILE" ]] && rm -f "$FLAGFILE"
    fi
    echo "$(timestamp): uso ${USAGE}%, abaixo do limite." >> "$LOGFILE"
fi
