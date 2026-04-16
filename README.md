# Calcolo Diluizioni

Web app per il calcolo agevolato delle diluizioni dei prodotti per il Car Detailing.

## Funzionalita'

- **Calcolatore**: calcolo rapido di prodotto + acqua dato volume e rapporto `1:X`
- **Rabbocco**: calcolo del top-up di una bottiglia parzialmente usata
- **Riferimento prodotti**: catalogo con usi e rapporti consigliati, selezione per
  marchio → prodotto
- **Area admin**: aggiunta / modifica / rimozione prodotti via interfaccia web
  (protetta da password, sessione PHP)

## Architettura in breve

- `diluizioni.html` — frontend SPA (HTML + CSS + JS inline, nessun build step)
- `api.php` — backend REST-ish (PHP 8.x, auth via sessione)
- `products.json` — catalogo prodotti persistito su disco (scritto da `api.php`)
- `config.php` — **git-ignored**, contiene l'hash bcrypt della password admin
- `lxc/` — documentazione di deploy sul container di produzione

Per i dettagli architetturali, le convenzioni di codice e le formule di calcolo
vedi [`CLAUDE.md`](CLAUDE.md).

## Utilizzo in locale

Serve PHP 8.x (l'app non e' piu' puramente statica: `api.php` legge e scrive
`products.json`).

```bash
# dalla root del repo
php -S localhost:8000
```

poi apri `http://localhost:8000/diluizioni.html`.

Per usare l'area admin in locale crea `config.php` con l'hash bcrypt di una
password di test (il file e' in `.gitignore`):

```bash
php -r "echo \"<?php\nconst ADMIN_PASSWORD_HASH = '\" . password_hash('admin', PASSWORD_BCRYPT) . \"';\n\";" > config.php
```

Con quel comando la password admin e' `admin`. Dopo il login la sessione viene
rigenerata (`session_regenerate_id`) e puoi usare le funzioni CRUD dal tab
"Admin" del frontend.

## Deploy

L'applicazione e' deployata in un **container LXC non privilegiato su Proxmox VE**
(Debian 13 Trixie + Nginx + PHP-FPM 8.4). Snapshot di produzione, runbook di
redeploy, gestione password admin e troubleshooting sono in
[`lxc/README.md`](lxc/README.md); la config Nginx versionata e' in
[`lxc/nginx-site.conf`](lxc/nginx-site.conf).

Non esiste piu' il vecchio flusso FTP + GitHub Actions: se qualcosa si rompe in
produzione, si diagnostica il container, non si ripristina FTP.
