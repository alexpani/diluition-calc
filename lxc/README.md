# Migrazione su LXC (Proxmox)

Questa cartella contiene tutto il necessario per migrare
**Calcolo Diluizioni** da un hosting web classico (attualmente
`activecloud.it` via FTP) a un container LXC non privilegiato
su **Proxmox VE**, con stack **Nginx + PHP-FPM**.

## Contenuto

| File | Dove si esegue | A cosa serve |
|------|----------------|--------------|
| `create-container.sh` | Host Proxmox (root)   | Crea il container LXC con `pct create` |
| `provision.sh`        | Dentro al container   | Installa nginx + php-fpm, crea utente `deploy` e web root |
| `nginx-site.conf`     | Dentro al container   | Virtual host Nginx per l'app |
| `deploy.sh`           | La tua workstation    | Rsync via SSH dei sorgenti nel container |

## Prerequisiti

- Host Proxmox VE con template Debian 12 scaricato
  (`pveam update && pveam download local debian-12-standard_12.2-1_amd64.tar.zst`).
- Una chiave SSH sulla tua workstation (`~/.ssh/id_ed25519.pub`).
- `rsync` installato sulla workstation.

## 1) Creare il container

Sulla macchina Proxmox, da root:

```bash
# Copia lo script e quelli correlati sull'host Proxmox
scp lxc/*.sh lxc/nginx-site.conf root@proxmox:/root/

# Poi sull'host
ssh root@proxmox
cd /root
CTID=120 HOSTNAME=calcolo-diluizioni IP=dhcp ./create-container.sh
```

Variabili utili (tutte opzionali, hanno un default):

| Variabile        | Default                                                   |
|------------------|-----------------------------------------------------------|
| `CTID`           | `120`                                                     |
| `HOSTNAME`       | `calcolo-diluizioni`                                      |
| `TEMPLATE`       | `local:vztmpl/debian-12-standard_12.2-1_amd64.tar.zst`    |
| `STORAGE`        | `local-lvm`                                               |
| `DISK_SIZE`      | `4` (GB)                                                  |
| `MEMORY`         | `512` (MB)                                                |
| `SWAP`           | `256` (MB)                                                |
| `CORES`          | `1`                                                       |
| `BRIDGE`         | `vmbr0`                                                   |
| `IP`             | `dhcp` (o es. `192.168.1.50/24,gw=192.168.1.1`)           |
| `SSH_PUBKEY_FILE`| `~/.ssh/id_ed25519.pub`                                   |

Lo script:
1. Crea il CT non privilegiato con `pct create`.
2. Lo avvia e attende che la rete funzioni.
3. Copia dentro `provision.sh` e `nginx-site.conf`.
4. Esegue `provision.sh` dentro al container.

Al termine viene stampato l'IP del container.

## 2) Configurare `.env` sulla workstation

Dalla root del repo:

```bash
cp .env.example .env
$EDITOR .env
```

Imposta almeno:

```
LXC_SSH_HOST=192.168.1.50
LXC_SSH_USER=deploy
LXC_SSH_PORT=22
LXC_WEB_ROOT=/var/www/calcolo-diluizioni
LXC_PHP_VERSION=8.2
```

Verifica la connettivita':

```bash
ssh deploy@192.168.1.50
```

## 3) Deploy manuale

```bash
./lxc/deploy.sh           # deploy reale
DRY_RUN=1 ./lxc/deploy.sh # simulazione
```

Cosa viene copiato:

- `diluizioni.html`
- `api.php`
- `products.json` **solo al primo deploy** (se il file non esiste ancora
  sul server, per non sovrascrivere le modifiche fatte via area admin).

Cosa NON viene copiato:

- `.git*`, `.env*`, `CLAUDE.md`, `README.md`
- `lxc/` (scripts di infra)
- `config.php` e `setup.php` (segreti, gestiti a parte)

## 4) Configurare l'area admin

`config.php` contiene l'hash della password admin e non e' versionato.
Va creato una tantum **dentro al container**:

```bash
# Dalla workstation
ssh deploy@<IP_CONTAINER>

# Dentro al container:
cd /var/www/calcolo-diluizioni
cat > config.php <<'PHP'
<?php
// Hash bcrypt della password admin
const ADMIN_PASSWORD_HASH = '$2y$10$....';
PHP
chmod 640 config.php
sudo chown deploy:www-data config.php
```

Per generare l'hash puoi usare:

```bash
php -r "echo password_hash('la-tua-password', PASSWORD_BCRYPT), PHP_EOL;"
```

## 5) Migrazione dei dati da activecloud

Se ci sono prodotti creati via area admin sull'hosting attuale, scarica
`products.json` via FTP prima di dismettere il vecchio sito e copialo
nel container:

```bash
# Dall'hosting vecchio (FTP client a scelta)
# -> scarica public_html/calcolo-diluizioni/products.json

scp products.json deploy@<IP_CONTAINER>:/var/www/calcolo-diluizioni/products.json
```

## 6) Esporre il container

Opzioni tipiche:

- **LAN only**: lascia il container sulla rete interna e accedi via IP.
- **Reverse proxy HTTPS** (consigliato): fai puntare un reverse proxy
  (Nginx Proxy Manager, Traefik, Caddy) al CT sulla porta 80 e gestisci
  TLS con Let's Encrypt.
- **Port forwarding**: sul router, inoltra `443 -> CT:80` dietro al reverse proxy.

## Troubleshooting

- **502 Bad Gateway**: controlla che `php-fpm` sia attivo e che il socket
  in `/etc/nginx/sites-available/calcolo-diluizioni` corrisponda a quello
  reale (`ls /run/php/`).
- **403 Forbidden**: permessi della web root. Deve essere
  `deploy:www-data` con `2775` sulle dir e `0644` sui file.
- **Login admin non funziona**: `config.php` non creato o password hash
  sbagliato (ricordati che e' bcrypt, non plaintext).
- **Deploy rsync rifiutato**: la chiave SSH non e' stata propagata su
  `deploy`. Verifica `~/.ssh/authorized_keys` dentro al container.

## Disattivare il vecchio deploy FTP

Il workflow GitHub Actions `.github/workflows/deploy.yml` e' stato
rimosso in questa migrazione. Se per qualche motivo ti serve ancora
deployare sul vecchio hosting, puoi ripristinarlo dallo storico git.
