#!/usr/bin/env bash
#
# deploy.sh
# ------------------------------------------------------------------
# Deploy manuale di Calcolo Diluizioni nel container LXC.
#
# Uso:
#     ./lxc/deploy.sh            # usa le variabili da .env
#     DRY_RUN=1 ./lxc/deploy.sh  # mostra cosa farebbe senza copiare
#
# Variabili richieste (da .env nella root del progetto):
#     LXC_SSH_HOST      es. 192.168.1.50  (IP del container)
#     LXC_SSH_USER      es. deploy
#     LXC_SSH_PORT      default: 22
#     LXC_WEB_ROOT      default: /var/www/calcolo-diluizioni
#     LXC_PHP_VERSION   default: 8.2
# ------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Carica .env se presente
if [[ -f "$PROJECT_ROOT/.env" ]]; then
  set -o allexport
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.env"
  set +o allexport
fi

LXC_SSH_HOST="${LXC_SSH_HOST:?Devi impostare LXC_SSH_HOST in .env}"
LXC_SSH_USER="${LXC_SSH_USER:-deploy}"
LXC_SSH_PORT="${LXC_SSH_PORT:-22}"
LXC_WEB_ROOT="${LXC_WEB_ROOT:-/var/www/calcolo-diluizioni}"
LXC_PHP_VERSION="${LXC_PHP_VERSION:-8.2}"

SSH_OPTS=(-p "$LXC_SSH_PORT" -o StrictHostKeyChecking=accept-new)
RSYNC_SSH="ssh ${SSH_OPTS[*]}"

DRY_FLAG=""
if [[ "${DRY_RUN:-0}" == "1" ]]; then
  DRY_FLAG="--dry-run"
  echo "[i] DRY RUN - nessuna modifica verra' scritta."
fi

echo "[+] Deploy verso ${LXC_SSH_USER}@${LXC_SSH_HOST}:${LXC_WEB_ROOT}"

# Elenco dei file/cartelle che DEVONO arrivare sul server.
# Nota: products.json NON viene sovrascritto (e' gestito via API admin).
INCLUDES=(
  "diluizioni.html"
  "api.php"
)

# Copia i file applicativi
rsync -avz --delete-after $DRY_FLAG \
  --rsh="$RSYNC_SSH" \
  --chmod=D2775,F0644 \
  --exclude='.git' \
  --exclude='.github' \
  --exclude='.env*' \
  --exclude='CLAUDE.md' \
  --exclude='README.md' \
  --exclude='lxc/' \
  --exclude='config.php' \
  --exclude='setup.php' \
  --exclude='products.json' \
  "${INCLUDES[@]}" \
  "${LXC_SSH_USER}@${LXC_SSH_HOST}:${LXC_WEB_ROOT}/"

# Primo bootstrap di products.json: copia solo se non esiste sul server
echo "[+] Verifico products.json sul server..."
if ssh "${SSH_OPTS[@]}" "${LXC_SSH_USER}@${LXC_SSH_HOST}" \
     "test ! -f ${LXC_WEB_ROOT}/products.json"; then
  echo "[i] products.json mancante: copio la versione iniziale dal repo."
  rsync -avz $DRY_FLAG --rsh="$RSYNC_SSH" \
    --chmod=F0664 \
    "$PROJECT_ROOT/products.json" \
    "${LXC_SSH_USER}@${LXC_SSH_HOST}:${LXC_WEB_ROOT}/products.json"
else
  echo "[i] products.json gia' presente: NON lo sovrascrivo."
fi

# Ricarica php-fpm per invalidare l'opcache (opzionale)
if [[ "${DRY_RUN:-0}" != "1" ]]; then
  echo "[+] Ricarico php${LXC_PHP_VERSION}-fpm..."
  ssh "${SSH_OPTS[@]}" "${LXC_SSH_USER}@${LXC_SSH_HOST}" \
    "sudo systemctl reload php${LXC_PHP_VERSION}-fpm" || \
    echo "[!] Reload php-fpm fallito (ignorabile se opcache non e' attivo)."
fi

echo "[OK] Deploy completato."
