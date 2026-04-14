# Deployment su LXC (Proxmox)

Questa cartella documenta **come e' attualmente deployata in produzione**
Calcolo Diluizioni e come fare i redeploy successivi. Non contiene piu'
gli script di bootstrap del container (sono stati rimossi perche' non mai
eseguiti davvero: il container e' stato provisionato a mano).

## Snapshot di produzione

| Ambito          | Valore                                                          |
|-----------------|-----------------------------------------------------------------|
| Host            | Proxmox VE                                                      |
| Container       | LXC non privilegiato, hostname `diluition-calc`                 |
| OS              | Debian 13 "Trixie" (13.4)                                       |
| Web server      | Nginx (distro package)                                          |
| Runtime PHP     | PHP 8.4 via `php-fpm`                                           |
| Socket PHP-FPM  | `/run/php/php-fpm.sock` (path stabile via update-alternatives)  |
| Web root        | `/var/www/calcolo-diluizioni`                                   |
| User/group      | `www-data:www-data`                                             |
| IP LAN          | `192.168.68.194/24` (DHCP, idealmente da bloccare con reservation) |
| Esposizione     | HTTP sulla LAN, nessun HTTPS / dominio pubblico al momento      |

Layout della web root:

```
/var/www/calcolo-diluizioni/
├── diluizioni.html   # 0644 www-data:www-data  (frontend SPA)
├── api.php           # 0644 www-data:www-data  (backend REST-ish)
├── products.json     # 0664 www-data:www-data  (dati, scrivibile da php-fpm)
└── config.php        # 0640 root:www-data      (hash bcrypt password admin)
```

Log utili sul container:

- `/var/log/nginx/calcolo-diluizioni.access.log`
- `/var/log/nginx/calcolo-diluizioni.error.log`
- `/var/log/php8.4-fpm.log`

## File versionati in questa cartella

- `nginx-site.conf` — snapshot della configurazione Nginx effettivamente
  installata in `/etc/nginx/sites-available/calcolo-diluizioni`.
  **Se la config sul server viene modificata, aggiornare anche questo file**
  nel repo per evitare drift.

## Redeploy di un cambiamento applicativo

Flusso standard dopo un merge su `main` (il branch `claude/...` o qualsiasi
altra via). I comandi vanno eseguiti **dentro al container** (via SSH oppure
dalla console Proxmox):

```bash
# 1) Aggiorna il clone di lavoro in /tmp
cd /tmp/diluition-calc
git fetch origin main
git checkout main
git reset --hard origin/main

# 2) Copia i file applicativi nella web root con permessi e owner corretti.
#    NON tocchiamo products.json (stato runtime) ne' config.php (segreto).
install -m 0644 -o www-data -g www-data diluizioni.html /var/www/calcolo-diluizioni/diluizioni.html
install -m 0644 -o www-data -g www-data api.php        /var/www/calcolo-diluizioni/api.php

# 3) Reload php-fpm per invalidare l'opcache di api.php e config.php
systemctl reload php8.4-fpm
```

Se il clone in `/tmp/diluition-calc` non esistesse (es. dopo un reboot con
`/tmp` in tmpfs), ricrealo con:

```bash
git clone https://github.com/alexpani/diluition-calc.git /tmp/diluition-calc
```

## Modificare la password admin

Dentro al container, senza che la password compaia in shell history:

```bash
read -s -p "Nuova password admin: " ADMIN_PW; echo
ADMIN_PW="$ADMIN_PW" php -r '
  $pw = getenv("ADMIN_PW");
  if ($pw === "" || $pw === false) { fwrite(STDERR, "password vuota, annullo\n"); exit(1); }
  $hash = password_hash($pw, PASSWORD_BCRYPT);
  $content = "<?php\nconst ADMIN_PASSWORD_HASH = " . var_export($hash, true) . ";\n";
  file_put_contents("/var/www/calcolo-diluizioni/config.php", $content);
  echo "Hash scritto.\n";
'
unset ADMIN_PW
chmod 0640 /var/www/calcolo-diluizioni/config.php
chown root:www-data /var/www/calcolo-diluizioni/config.php
systemctl reload php8.4-fpm
```

Per **disabilitare** l'area admin, rimetti `ADMIN_PASSWORD_HASH = ''` in
`config.php`: l'endpoint `login` rispondera' `503 "Password admin non impostata"`
e l'app smettera' di accettare login.

## Backup dei dati

L'unico file che contiene dati mutabili dal runtime e' `products.json`.
Copialo a mano quando serve:

```bash
# Dalla workstation
scp root@192.168.68.194:/var/www/calcolo-diluizioni/products.json ./products-backup-$(date +%F).json
```

`config.php` e' un segreto, non metterlo in backup insieme al repo.

## Aggiornare la config Nginx

Se modifichi `nginx-site.conf` nel repo, ricordati di propagarlo al server:

```bash
# Dentro al container, dopo aver git-pullato
install -m 0644 -o root -g root lxc/nginx-site.conf /etc/nginx/sites-available/calcolo-diluizioni
nginx -t && systemctl reload nginx
```

## Ricostruire il container da zero

Non ci sono piu' script di bootstrap in questa cartella: il container e'
stato fatto a mano. Se un giorno dovessi ricrearlo, la sintesi dei passi e':

1. Sull'host Proxmox, `pct create <CTID> local:vztmpl/debian-13-standard_*.tar.zst`
   con `--unprivileged 1`, rete bridge, 512 MB RAM / 4 GB disco bastano.
2. Dentro al container: `apt update && apt install -y nginx php-fpm php-mbstring git`.
3. `install -d -m 0755 -o www-data -g www-data /var/www/calcolo-diluizioni`.
4. Copiare questo `nginx-site.conf` in `/etc/nginx/sites-available/calcolo-diluizioni`,
   `ln -sf` in `sites-enabled/`, rimuovere il site `default`, `nginx -t && systemctl reload nginx`.
5. `git clone` del repo in `/tmp`, poi seguire la sezione "Redeploy" qui sopra.
6. Creare `config.php` con la sezione "Modificare la password admin".

## Troubleshooting rapido

- **502 Bad Gateway**: `systemctl status php8.4-fpm`; `ls -l /run/php/`. Verifica
  che `/run/php/php-fpm.sock` esista e sia `srw-rw---- www-data www-data`.
- **403 Forbidden**: permessi sbagliati sulla web root.
  Atteso: `drwxr-xr-x www-data:www-data` sulla dir, `-rw-r--r--` sui file, eccetto
  `config.php` che e' `-rw-r----- root:www-data`.
- **Login admin → "Password admin non impostata" (503)**: `config.php` manca o
  ha `ADMIN_PASSWORD_HASH = ''`. Segui la sezione "Modificare la password admin".
- **Login admin → "Password errata"**: hash sbagliato in `config.php`. Rigenera.
- **Dopo redeploy l'app sembra "vecchia"**: Ctrl+F5 nel browser per bypassare la
  cache, e controlla che `systemctl reload php8.4-fpm` sia stato eseguito (opcache).
