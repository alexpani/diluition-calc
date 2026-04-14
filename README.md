# Calcolo Diluizioni

Web app per il calcolo agevolato delle diluizioni dei prodotti per il Car Detailing.

## Funzionalita'

- **Calcolatore**: calcolo rapido di prodotto + acqua dato volume e rapporto `1:X`
- **Rabbocco**: calcolo del top-up di una bottiglia parzialmente usata
- **Riferimento prodotti**: catalogo con usi e rapporti consigliati
- **Area admin**: aggiunta/modifica/rimozione prodotti via interfaccia web (protetta da password)

## Utilizzo in locale

L'app e' costituita da `diluizioni.html` (frontend SPA) + `api.php` (backend che
legge e scrive `products.json`). Per farla girare in locale serve PHP:

```bash
# dalla root del repo
php -S localhost:8000
```

poi apri `http://localhost:8000/diluizioni.html`.

Per usare l'area admin in locale crea `config.php` con l'hash bcrypt di una
password di test:

```bash
php -r "echo \"<?php\nconst ADMIN_PASSWORD_HASH = '\" . password_hash('admin', PASSWORD_BCRYPT) . \"';\n\";" > config.php
```

## Deploy

L'applicazione e' deployata in un **container LXC su Proxmox** (Debian 13 + Nginx + PHP-FPM).
Tutti gli script di provisioning, la config Nginx, lo script di deploy e le istruzioni
passo per passo sono in [`lxc/README.md`](lxc/README.md).
