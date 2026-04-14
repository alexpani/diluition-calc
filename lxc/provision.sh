#!/usr/bin/env bash
#
# provision.sh
# ------------------------------------------------------------------
# Script di provisioning che gira DENTRO il container LXC Debian.
# Installa nginx + PHP-FPM, prepara la web root e l'utente di deploy.
#
# Viene invocato automaticamente da create-container.sh, ma puo'
# essere eseguito anche manualmente:
#     pct exec <CTID> -- /root/provision.sh
# ------------------------------------------------------------------
set -euo pipefail

WEB_ROOT="${WEB_ROOT:-/var/www/calcolo-diluizioni}"
DEPLOY_USER="${DEPLOY_USER:-deploy}"
PHP_VERSION="${PHP_VERSION:-8.4}"
SITE_NAME="calcolo-diluizioni"

export DEBIAN_FRONTEND=noninteractive

echo "[+] Aggiornamento pacchetti base..."
apt-get update -y
apt-get upgrade -y

echo "[+] Installazione nginx, PHP-FPM e utility..."
# Nota: php-json non e' piu' un pacchetto separato (JSON e' built-in in PHP 8+).
apt-get install -y --no-install-recommends \
  nginx \
  php-fpm \
  php-mbstring \
  rsync \
  sudo \
  ca-certificates \
  curl \
  openssh-server

# Rileva la versione di PHP effettivamente installata (sovrascrive il default)
if command -v php >/dev/null 2>&1; then
  PHP_VERSION="$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
fi
PHP_SOCK="/run/php/php${PHP_VERSION}-fpm.sock"
echo "[i] Uso PHP ${PHP_VERSION} (socket: ${PHP_SOCK})"

echo "[+] Creazione utente di deploy: ${DEPLOY_USER}"
if ! id "$DEPLOY_USER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$DEPLOY_USER"
fi
usermod -aG www-data "$DEPLOY_USER"

# Propaga la chiave SSH di root (iniettata da pct) anche a deploy
if [[ -f /root/.ssh/authorized_keys ]]; then
  install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/${DEPLOY_USER}/.ssh"
  install -m 600 -o "$DEPLOY_USER" -g "$DEPLOY_USER" \
    /root/.ssh/authorized_keys "/home/${DEPLOY_USER}/.ssh/authorized_keys"
fi

echo "[+] Creazione web root: ${WEB_ROOT}"
install -d -m 2775 -o "$DEPLOY_USER" -g www-data "$WEB_ROOT"

echo "[+] Installazione config Nginx..."
if [[ -f /root/nginx-site.conf ]]; then
  # sostituisci il socket PHP con la versione effettiva
  sed "s|__PHP_SOCK__|${PHP_SOCK}|g; s|__WEB_ROOT__|${WEB_ROOT}|g" \
    /root/nginx-site.conf > "/etc/nginx/sites-available/${SITE_NAME}"
else
  echo "[!] /root/nginx-site.conf non trovato; salto la config custom." >&2
fi

ln -sf "/etc/nginx/sites-available/${SITE_NAME}" "/etc/nginx/sites-enabled/${SITE_NAME}"
rm -f /etc/nginx/sites-enabled/default

# Permetti a deploy di ricaricare nginx/php-fpm senza password
cat > /etc/sudoers.d/deploy-reload <<EOF
${DEPLOY_USER} ALL=(root) NOPASSWD: /bin/systemctl reload nginx, /bin/systemctl reload php${PHP_VERSION}-fpm
EOF
chmod 440 /etc/sudoers.d/deploy-reload

echo "[+] Test config nginx..."
nginx -t

echo "[+] Abilito e avvio i servizi..."
systemctl enable --now "php${PHP_VERSION}-fpm"
systemctl enable --now nginx
systemctl reload nginx

# File placeholder finche' il primo deploy non copia i sorgenti
if [[ ! -f "${WEB_ROOT}/diluizioni.html" ]]; then
  cat > "${WEB_ROOT}/index.html" <<'EOF'
<!doctype html>
<meta charset="utf-8">
<title>Calcolo Diluizioni - in allestimento</title>
<h1>Container pronto</h1>
<p>Esegui <code>lxc/deploy.sh</code> dalla workstation per copiare i file.</p>
EOF
  chown "$DEPLOY_USER:www-data" "${WEB_ROOT}/index.html"
fi

echo
echo "[OK] Provisioning completato."
echo "    Web root : ${WEB_ROOT}"
echo "    Utente   : ${DEPLOY_USER}"
echo "    PHP-FPM  : ${PHP_SOCK}"
