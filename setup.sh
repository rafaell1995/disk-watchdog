#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/rafaell1995/disk-watchdog/main}"
SERVICE_PATH="/etc/systemd/system/disk-watchdog.service"
TIMER_PATH="/etc/systemd/system/disk-watchdog.timer"
SCRIPT_DEST="/usr/local/bin/disk-watchdog.sh"
ENV_DIR="/etc/disk-watchdog"
ENV_CONF="$ENV_DIR/env.conf"

usage() {
    cat <<EOF
Uso: $0 [OPÇÕES]

Opções:
--help Mostra essa ajuda.
--update-scripts Baixa/atualiza apenas o script e as unidades systemd, sem tocar em env.conf.
--reconfigure Reconfigura interativamente o env.conf (faz backup do anterior).
--force Atualiza tudo e força reconfiguração (equivalente a --update-scripts + --reconfigure).

Sem opções, faz install padrão: atualiza scripts/unidades e interage para criar/env.conf (se já existir pergunta se mantém).
EOF
}

# Ensure running as root
if [[ "$EUID" -ne 0 ]]; then
    echo "Precisamos de privilégios de root. Reexecutando com sudo..."
    exec sudo bash "$0" "$@"
fi

# Parse flags
DO_UPDATE_SCRIPTS=false
DO_RECONFIGURE=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help)
            usage
            exit 0
            ;;
        --update-scripts)
            DO_UPDATE_SCRIPTS=true
            shift
            ;;
        --reconfigure)
            DO_RECONFIGURE=true
            shift
            ;;
        --force)
            FORCE=true
            DO_UPDATE_SCRIPTS=true
            DO_RECONFIGURE=true
            shift
            ;;
        *)
            echo "Opção desconhecida: $1"
            usage
            exit 1
            ;;
    esac
done

# Check for systemctl
if ! command -v systemctl>/dev/null; then
    echo "Erro: systemctl não encontrado. Precisa de um sistema com systemd."
    exit 1
fi

# Downloader helper (curl preferred, fallback to wget)
download() {
    local url=$1
    local dest=$2

    if command -v curl >/dev/null; then
        curl -fsSL "$url" -o "$dest"
    elif command -v wget >/dev/null; then
        wget -qO "$dest" "$url"
    else
        echo "Nenhum downloader disponível (curl ou wget). Instale um deles."
        exit 1
    fi
}

echo "==> Etapa 1: atualizando script e unidades systemd"
if [[ "$DO_UPDATE_SCRIPTS" = true || "$FORCE" = true || ( "$DO_UPDATE_SCRIPTS" = false && "$DO_RECONFIGURE" = false ) ]]; then
    # padrão: faz update de scripts/unidades
    download "$REPO_RAW/disk-watchdog.sh" "$SCRIPT_DEST"
    chmod +x "$SCRIPT_DEST"
    chmod 755 "$SCRIPT_DEST"
    echo " -> script instalado/atualizado em $SCRIPT_DEST"

    download "$REPO_RAW/disk-watchdog.service" "$SERVICE_PATH"
    download "$REPO_RAW/disk-watchdog.timer" "$TIMER_PATH"
    echo " -> unidades systemd instaladas/atualizadas em:"
    echo " $SERVICE_PATH"
    echo " $TIMER_PATH"
else
    echo " -> pulando atualização de script/unidades (não solicitado)."
fi

echo
echo "==> Etapa 2: configuração do env.conf"
mkdir -p "$ENV_DIR"
if [[ -f "$ENV_CONF" && "$DO_RECONFIGURE" = false && "$FORCE" = false ]]; then
    read -rp "Arquivo de configuração já existe em $ENV_CONF. Deseja mantê-lo? [Y/n]: " keep
    keep=${keep:-Y}
    if [[ "$keep" =~ ^[Yy]$ ]]; then
        echo " -> mantendo configuração existente."
    else
        DO_RECONFIGURE=true
    fi
fi

if [[ "$DO_RECONFIGURE" = true || "$FORCE" = true ]]; then
    # backup se existir
    if [[ -f "$ENV_CONF" ]]; then
        timestamp=$(date +"%Y%m%d%H%M%S")
        cp "$ENV_CONF" "${ENV_CONF}.bak.$timestamp"
        echo " -> backup do env.conf anterior salvo em ${ENV_CONF}.bak.$timestamp"
    fi

    # Interactive prompt
    read -rp "Discord webhook URL: " webhook
    while [[ -z "$webhook" || "$webhook" != *"discord.com/api/webhooks/"* ]]; do
        echo "URL inválida. Deve conter 'discord.com/api/webhooks/'."
        read -rp "Discord webhook URL: " webhook
    done

    read -rp "Threshold de alerta em % (padrão 85): " threshold_input
    threshold=${threshold_input:-85}
    while ! [[ "$threshold" =~ ^[0-9]+$ ]] || (( threshold <= 0 )) || (( threshold>= 100 )); do
        echo "Valor inválido. Digite um número entre 1 e 99."
        read -rp "Threshold de alerta em % (padrão 85): " threshold_input
        threshold=${threshold_input:-85}
    done

    read -rp "Margem de recuperação em % (padrão 5): " margin_input
    recover_margin=${margin_input:-5}
    while ! [[ "$recover_margin" =~ ^[0-9]+$ ]] || (( recover_margin < 0 )) || (( recover_margin>= threshold )); do
        echo "Valor inválido. Deve ser >=0 e menor que threshold ($threshold)."
        read -rp "Margem de recuperação em % (padrão 5): " margin_input
        recover_margin=${margin_input:-5}
    done

    read -rp "Nome do servidor (opcional, será usado nos alertas; enter para usar hostname): " server_name

    # Escreve env.conf
    {
        echo "DISCORD_WEBHOOK_URL=\"$webhook\""
        echo "THRESHOLD=$threshold"
        echo "RECOVER_MARGIN=$recover_margin"
        if [[ -n "${server_name// /}" ]]; then
            echo "SERVER_NAME=\"$server_name\""
        fi
    } > "$ENV_CONF"

    chmod 600 "$ENV_CONF"
    echo " -> criado/atualizado $ENV_CONF com permissões restritas"
else
    echo " -> pulando reconfiguração do env.conf."
fi

echo
echo "==> Etapa 3: recarregando e (re)habilitando o timer"

systemctl daemon-reload
systemctl enable --now disk-watchdog.timer

echo
echo "✅ Resultado:"
echo " - Serviço/unit/timer: disk-watchdog.timer"
echo " - Configuração usada: $ENV_CONF"
echo
echo "Comandos úteis:"
echo " Ver status do timer: sudo systemctl status disk-watchdog.timer"
echo " Ver logs da execução: sudo journalctl -u disk-watchdog.service"
echo " Forçar execução manual: sudo $SCRIPT_DEST"
echo
echo "Se quiser reconfigurar só o env.conf mais tarde: sudo $0 --reconfigure"
echo "Para atualizar script/unidades sem tocar config: sudo $0 --update-scripts"
echo "Para forçar tudo (reconfigura + atualiza): sudo $0 --force"