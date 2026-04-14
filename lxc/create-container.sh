#!/usr/bin/env bash
#
# create-container.sh
# ------------------------------------------------------------------
# Crea un container LXC non privilegiato su Proxmox VE per ospitare
# l'applicazione "Calcolo Diluizioni".
#
# Uso (da eseguire sull'host Proxmox come root):
#     ./create-container.sh
#
# Le variabili qui sotto possono essere sovrascritte da env:
#     CTID=120 HOSTNAME=calcolo-diluizioni ./create-container.sh
# ------------------------------------------------------------------
set -euo pipefail

CTID="${CTID:-120}"
HOSTNAME="${HOSTNAME:-calcolo-diluizioni}"
TEMPLATE="${TEMPLATE:-local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst}"
STORAGE="${STORAGE:-local-lvm}"
DISK_SIZE="${DISK_SIZE:-4}"           # GB
MEMORY="${MEMORY:-512}"               # MB
SWAP="${SWAP:-256}"                   # MB
CORES="${CORES:-1}"
BRIDGE="${BRIDGE:-vmbr0}"
IP="${IP:-dhcp}"                      # es. "192.168.1.50/24,gw=192.168.1.1"
UNPRIVILEGED="${UNPRIVILEGED:-1}"
ROOT_PASSWORD="${ROOT_PASSWORD:-}"    # se vuota, viene generata
SSH_PUBKEY_FILE="${SSH_PUBKEY_FILE:-$HOME/.ssh/id_ed25519.pub}"

if ! command -v pct >/dev/null 2>&1; then
  echo "[!] Questo script va eseguito su un host Proxmox VE (pct non trovato)." >&2
  exit 1
fi

if pct status "$CTID" >/dev/null 2>&1; then
  echo "[!] Il container $CTID esiste gia'. Aborto." >&2
  exit 1
fi

if [[ -z "$ROOT_PASSWORD" ]]; then
  ROOT_PASSWORD="$(openssl rand -base64 18)"
  echo "[i] Password root generata: $ROOT_PASSWORD"
  echo "[i] Salvala subito: non verra' mostrata di nuovo."
fi

if [[ ! -f "$SSH_PUBKEY_FILE" ]]; then
  echo "[!] Chiave pubblica SSH non trovata in $SSH_PUBKEY_FILE" >&2
  echo "    Generala con: ssh-keygen -t ed25519" >&2
  exit 1
fi

if [[ "$IP" == "dhcp" ]]; then
  NET="name=eth0,bridge=${BRIDGE},ip=dhcp"
else
  NET="name=eth0,bridge=${BRIDGE},ip=${IP}"
fi

echo "[+] Creazione CT $CTID ($HOSTNAME) ..."
pct create "$CTID" "$TEMPLATE" \
  --hostname "$HOSTNAME" \
  --cores "$CORES" \
  --memory "$MEMORY" \
  --swap "$SWAP" \
  --rootfs "${STORAGE}:${DISK_SIZE}" \
  --net0 "$NET" \
  --unprivileged "$UNPRIVILEGED" \
  --features "nesting=1" \
  --onboot 1 \
  --password "$ROOT_PASSWORD" \
  --ssh-public-keys "$SSH_PUBKEY_FILE" \
  --ostype debian \
  --start 1

echo "[+] Attendo che il container sia pronto..."
sleep 3
pct exec "$CTID" -- bash -c 'until getent hosts deb.debian.org >/dev/null 2>&1; do sleep 1; done'

echo "[+] Copio provision.sh dentro al container..."
pct push "$CTID" "$(dirname "$0")/provision.sh" /root/provision.sh --perms 755
pct push "$CTID" "$(dirname "$0")/nginx-site.conf" /root/nginx-site.conf

echo "[+] Eseguo il provisioning..."
pct exec "$CTID" -- /root/provision.sh

echo
echo "======================================================================"
echo "[OK] Container $CTID ($HOSTNAME) pronto."
echo "     IP: $(pct exec "$CTID" -- hostname -I | awk '{print $1}')"
echo
echo "Prossimi step (dalla tua workstation):"
echo "  1. cp .env.example .env   # e compila le variabili LXC_*"
echo "  2. ./lxc/deploy.sh        # copia i sorgenti nel container"
echo "  3. Crea config.php con l'hash della password admin dentro al CT"
echo "======================================================================"
