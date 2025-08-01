#!/bin/bash

# preserva overrides do ambiente para que tenham precedência
have_threshold_override=0
have_recover_margin_override=0
have_discord_override=0
have_server_name_override=0
if [[ -v THRESHOLD ]]; then saved_threshold="$THRESHOLD"; have_threshold_override=1; fi
if [[ -v RECOVER_MARGIN ]]; then saved_recover_margin="$RECOVER_MARGIN"; have_recover_margin_override=1; fi
if [[ -v DISCORD_WEBHOOK_URL ]]; then saved_discord_webhook_url="$DISCORD_WEBHOOK_URL"; have_discord_override=1; fi
if [[ -v SERVER_NAME ]]; then saved_server_name="$SERVER_NAME"; have_server_name_override=1; fi

# fallback: carrega o env.conf se existir (útil para execução manual e via systemd)
ENV_CONF_FILE="/etc/disk-watchdog/env.conf"
if [[ -f "$ENV_CONF_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_CONF_FILE"
  # limpa possíveis carriage returns (ex: se editado com CRLF)
  DISCORD_WEBHOOK_URL=${DISCORD_WEBHOOK_URL//$'\r'/}
  SERVER_NAME=${SERVER_NAME//$'\r'/}
fi

# restaura overrides se existiam
if (( have_threshold_override )); then THRESHOLD="$saved_threshold"; fi
if (( have_recover_margin_override )); then RECOVER_MARGIN="$saved_recover_margin"; fi
if (( have_discord_override )); then DISCORD_WEBHOOK_URL="$saved_discord_webhook_url"; fi
if (( have_server_name_override )); then SERVER_NAME="$saved_server_name"; fi

# Configurações via variáveis de ambiente (com fallback/default)
THRESHOLD=${THRESHOLD:-85}
RECOVER_MARGIN=${RECOVER_MARGIN:-5}
DISCORD_WEBHOOK_URL=${DISCORD_WEBHOOK_URL:-}
FLAGFILE=${FLAGFILE:-/var/run/disk_watchdog_alerted}
LOGFILE=${LOGFILE:-/var/log/disk-watchdog.log}

# Identificação do servidor (override opcional via SERVER_NAME)
if [[ -n "${SERVER_NAME:-}" ]]; then
  SERVER_DISPLAY="$SERVER_NAME"
else
  SERVER_DISPLAY=$(hostname -f 2>/dev/null || hostname)
fi

timestamp() { date "+%F %T"; }

# debug: loga configuração inicial (mas não imprime o webhook inteiro)
if [[ "${DEBUG:-0}" == "1" ]]; then
  masked_webhook=""
  if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
    masked_webhook="${DISCORD_WEBHOOK_URL:0:30}... (len=${#DISCORD_WEBHOOK_URL})"
  else
    masked_webhook="(não configurado)"
  fi
  echo "$(timestamp): [debug] THRESHOLD=$THRESHOLD RECOVER_MARGIN=$RECOVER_MARGIN SERVER_DISPLAY=$SERVER_DISPLAY WEBHOOK=$masked_webhook" >> "$LOGFILE"
fi

# Pega uso da partição raiz (/), em %
USAGE=$(df -P / | awk 'NR==2 {gsub(/%/,""); print $5}')

# Envia alerta para Discord (se configurado)
send_alert() {
    local msg="$1"
    echo "$(timestamp): $msg" >> "$LOGFILE"

    if [[ -n "$DISCORD_WEBHOOK_URL" ]]; then
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
    if (( USAGE < THRESHOLD - RECOVER_MARGIN )); then
        [[ -f "$FLAGFILE" ]] && rm -f "$FLAGFILE"
    fi
    echo "$(timestamp): uso ${USAGE}%, abaixo do limite." >> "$LOGFILE"
fi
