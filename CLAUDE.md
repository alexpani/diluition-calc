# CLAUDE.md - AI Assistant Guidelines for Calcolo Diluizioni

## Project Overview

**Calcolo Diluizioni** (Dilution Calculator) is a single-page web application for calculating product dilution ratios, primarily targeting car care and detailing products. The app is written entirely in Italian.

## Quick Start

The frontend (`diluizioni.html`) talks to a PHP backend (`api.php`) that reads
and writes `products.json`, so a PHP-capable server is required — a plain
static server is no longer enough.

```bash
# From the repo root
php -S localhost:8000
# Then open http://localhost:8000/diluizioni.html
```

For the admin area to work in local dev, create a `config.php` with a bcrypt
hash (the file is git-ignored):

```bash
php -r "echo \"<?php\nconst ADMIN_PASSWORD_HASH = '\" . password_hash('admin', PASSWORD_BCRYPT) . \"';\n\";" > config.php
```

## Project Structure

```
calcolo-diluizioni/
├── CLAUDE.md            # This file - AI assistant guidelines
├── README.md            # Project description (Italian)
├── diluizioni.html      # Frontend SPA (HTML + CSS + JS in one file)
├── api.php              # Backend REST-ish API (products CRUD + admin auth)
├── products.json        # Persistent product catalog (written by api.php)
├── config.php           # [git-ignored] admin password hash
├── setup.php            # [git-ignored] one-shot admin password setup helper
└── lxc/                 # LXC deployment documentation
    ├── README.md        # Production snapshot + redeploy runbook
    └── nginx-site.conf  # Versioned copy of the production Nginx site
```

### File Organization (diluizioni.html)

| Section | Lines | Description |
|---------|-------|-------------|
| HTML Head & Meta | 1-6 | Document declaration, UTF-8, viewport |
| CSS Styles | 7-557 | Complete inline stylesheet |
| HTML Structure | 558-758 | Tab-based UI (calcolatore, rabbocco, prodotti, admin) + modal prodotto |
| JavaScript | 759-1325 | Application logic (data is loaded at runtime from `api.php`) |
| Closing Tags | 1326-1327 | `</body>` and `</html>` |

Line numbers drift whenever the file is edited — treat them as a current
snapshot, not load-bearing. Prefer `grep -n "function foo"` to locate things.

## Architecture

### Technology Stack

- **Frontend**: HTML5 + CSS3 + Vanilla ES6+ in a single file (`diluizioni.html`)
- **Backend**: PHP 8.x (`api.php`) — stateless except for a PHP session used for admin auth
- **Persistence**: flat JSON file (`products.json`) written by `api.php`
- **Web server**: Nginx + PHP-FPM (production, LXC container)
- **No build process**: the frontend is served as-is, no bundler, no transpiler

### Key Design Decisions

1. **Frontend in one file**: all HTML, CSS, and JS in `diluizioni.html` for simplicity
2. **Minimal backend**: `api.php` is a single PHP file with a handful of REST-ish endpoints; no framework
3. **No database**: products live in `products.json` on disk, read/written by `api.php`. Good enough for the scale of the app.
4. **Mobile-first**: Container max-width 480px with responsive adjustments
5. **State-driven UI**: Simple state variables (`selectedVolume`, `selectedRatio`, etc.)

## Core Features

### 1. Calcolatore (Calculator Tab)
- Main dilution calculator using ratio format 1:X
- Preset buttons for common volumes and ratios
- Auto-calculation when presets selected

### 2. Rabbocco (Refill Tab)
- Calculates how to refill bottles with existing diluted product
- Validates feasibility and shows appropriate error messages
- Tracks existing concentrate in bottle

### 3. Riferimento Prodotti (Products Tab)
- Reference guide for the supported cleaning products
- Two-step selection: brand dropdown (`#brand-select`) → product dropdown
  (`#product-select`, only visible once a brand is picked)
- Each product has a category badge, optional note, and a list of usage
  scenarios with recommended ratios
- Clicking a use auto-sets the ratio and switches to Calculator tab
- The list is loaded at startup via `GET /api.php` (reads `products.json`)

### 4. Area Admin (password protected)
- Login via `POST /api.php?action=login` (bcrypt password check in `config.php`)
- Session-based auth (PHP `$_SESSION['admin']`); login calls
  `session_regenerate_id(true)` to prevent session fixation
- CRUD operations on products: add / update / delete, persisted in `products.json`
- UI exposed inside `diluizioni.html` when the user is authenticated:
  grouped-by-brand product list + modal form (`#product-modal`) for
  add/edit with a dynamic list of "utilizzi"

## Code Conventions

### Naming

- **Functions**: camelCase (`calculateRefill`, `renderVolumePresets`)
- **Variables**: camelCase (`selectedVolume`, `volumePresets`)
- **CSS Classes**: kebab-case (`tab-content`, `btn-primary`, `result-row`)
- **IDs**: kebab-case (`calc-result`, `product-select`)

### JavaScript Patterns

```javascript
// State management - simple variables
let selectedVolume = '';
let selectedRatio = '';

// Render functions - return HTML strings via template literals
function renderVolumePresets() {
  container.innerHTML = volumePresets.map(v =>
    `<button class="preset-btn" onclick="selectVolume(${v})">${formatVolume(v)}</button>`
  ).join('');
}

// Event handlers - inline onclick for presets, addEventListener for inputs
document.getElementById('volume').addEventListener('input', function() { ... });
```

### CSS Color System (Tailwind-inspired)

- Primary Blue: `#2563eb`
- Cyan: `#0891b2`
- Green: `#16a34a`
- Red: `#dc2626`
- Gray scale: `#f9fafb` to `#1f2937`

## Key Calculation Formulas

### Basic Dilution (1:X ratio)
```javascript
// For ratio 1:X, total parts = 1 + X
totalParts = 1 + ratio;
product = volume / totalParts;
water = product * ratio;
```

### Refill Calculation
```javascript
// currentR = current ratio in the bottle, targetR = desired ratio after refill
existingConcentrate    = remaining / (1 + currentR);
totalConcentrateNeeded = bottle    / (1 + targetR);
concentrateToAdd       = totalConcentrateNeeded - existingConcentrate;
volumeToAdd            = bottle - remaining;
waterToAdd             = volumeToAdd - concentrateToAdd;
```

## Common Development Tasks

### Adding a New Product

Products are **not** hardcoded in `diluizioni.html` — the `products` array is
loaded at runtime from `GET /api.php`. There are two supported workflows:

1. **Admin UI (preferred)**: log into the Admin tab and use "+ Aggiungi
   prodotto". The new product is persisted to `products.json` via
   `POST /api.php?action=add`, which assigns a numeric `id`.
2. **Direct edit of `products.json`** (local dev / bootstrap / seed):

   ```json
   {
     "id": 9,
     "brand": "Brand Name",
     "name": "Product Name",
     "category": "Category",
     "note": null,
     "uses": [
       { "name": "Use case 1", "ratio": 10 },
       { "name": "Use case 2", "ratio": "5-10", "ratioValue": 5 }
     ]
   }
   ```

Notes:
- `ratio` can be a number or a string (for ranges like `"5-10"` or `"puro"`)
- When `ratio` is a string, provide `ratioValue` for the numeric default
  used when the user clicks the button
- If editing `products.json` by hand, keep `id`s unique — `api.php` assigns
  new ones as `max(id) + 1`

### Adding a Preset Ratio

Edit the `ratioPresets` array in `diluizioni.html`:
```javascript
const ratioPresets = [1, 2, 3, ..., 1200, YOUR_NEW_RATIO];
```

### Adding a Preset Volume

Edit the `volumePresets` array in `diluizioni.html`:
```javascript
const volumePresets = [500, 1000, 2000, ..., YOUR_NEW_VOLUME];
```

### Adding a Bottle Preset

Edit the `bottlePresets` array in `diluizioni.html`:
```javascript
const bottlePresets = [500, 750, 1000, YOUR_NEW_BOTTLE];
```

All three preset arrays are declared together near the top of the `<script>`
block (`grep -n "volumePresets" diluizioni.html`).

### Modifying Calculations

- Basic dilution: `calculate()` function in `diluizioni.html`
- Refill logic: `calculateRefill()` function in `diluizioni.html`

### Styling Changes

All CSS is inline in the `<style>` block at the top of `diluizioni.html`.
Key classes:
- `.card` - Main container
- `.tab` / `.tab-content` - Tab system
- `.preset-btn` - Preset buttons
- `.result` - Result display boxes
- `.btn-primary` / `.btn-secondary` / `.btn-logout` - Action buttons
- `.product-card` / `.product-category-badge` - Products tab
- `.modal-overlay` / `.modal-box` - Admin add/edit product modal

## Data Structures

### Product Schema

Matches the shape written by `api.php` into `products.json`. Each product has
a stable `id` generated server-side on creation:

```javascript
{
  id: number,             // Numeric ID, auto-incremented by api.php
  brand: string,          // Brand (e.g., "Cleantle", "Labocosmetica")
  name: string,           // Product name
  category: string,       // Category (e.g., "APC", "Shampoo")
  note: string | null,    // Optional free-text note
  uses: [{
    name: string,         // Use case description
    ratio: number|string, // Ratio value or range
    ratioValue?: number   // Optional: default value for ranges
  }]
}
```

### Presets
```javascript
volumePresets = [500, 1000, 2000, 5000, 8000, 10000, 12000];     // ml
ratioPresets = [1,2,3,...,10,15,20,...,100,200,300,400,800,1000,1200]; // 29 values
bottlePresets = [500, 750, 1000];                                  // ml (refill tab)
```

### Current Products

The authoritative list is in `products.json` and can drift at runtime because
it is editable via the admin UI. As of the last seed: 1 Cleantle + 7
Labocosmetica products. Don't rely on this list in code — always read from
`products.json` / `GET /api.php`.

### Key Functions Reference

All functions live in the `<script>` block of `diluizioni.html`. Line numbers
are approximate and drift with edits — use `grep -n "function foo"` for the
current location.

| Function | Purpose |
|----------|---------|
| `init()` | Bootstraps the app: fetches products, renders presets, wires tabs, checks auth |
| `fetchProducts()` | `GET /api.php` → populates the in-memory `products` array |
| `formatVolume(ml)` | Formats ml to "Xml" or "XL" display |
| `escapeHtml(str)` | Escapes user-supplied strings before interpolating into HTML |
| `getUniqueBrands()` | Returns the sorted list of distinct brands for the Products tab |
| `renderVolumePresets()` / `renderRatioPresets()` / `renderBottlePresets()` | Render preset button rows |
| `renderBrandSelect()` | Populates the brand dropdown on the Products tab |
| `selectProductUse(btn)` | Reads `data-name` / `data-ratio-value` from the clicked button, sets the ratio, switches to Calculator |
| `setActiveTab(id)` / `setupTabs()` | Tab switching |
| `selectVolume(v)` / `selectRatio(r)` / `selectBottle(b)` | Handle preset selection (also keep the inputs in sync) |
| `updateVolumeButtons()` / `updateRatioButtons()` / `updateBottleButtons()` | Highlight the preset matching the current input value |
| `calculate()` | Main dilution calculation (Calculator tab) |
| `calculateRefill()` | Refill/top-up calculation (Rabbocco tab) |
| `checkAuth()` / `showAdminLogin()` / `showAdminContent()` | Admin auth state handling |
| `adminLogin()` / `adminLogout()` | Login/logout against `api.php` |
| `renderAdminProductList()` | Renders the grouped-by-brand admin list with edit/delete buttons |
| `showProductForm(id?)` / `closeProductForm()` | Open/close the add/edit modal |
| `createUseRow(use?)` / `addUse()` | Manage the dynamic "utilizzi" list inside the modal |
| `saveProduct()` | POST (add) or PUT (edit) against `api.php`, then refreshes the UI |
| `confirmDeleteProduct(id)` | DELETE against `api.php` |

## Backend API (`api.php`)

A single-file PHP endpoint. Routing is based on the HTTP method plus a
`?action=...` query parameter. Session-based auth: the admin login sets
`$_SESSION['admin'] = true` and subsequent write operations call
`requireAuth()`.

| Method | Action      | Auth  | Purpose |
|--------|-------------|-------|---------|
| GET    | (none)      | none  | Returns the raw content of `products.json` |
| GET    | `check`     | none  | Returns `{authenticated: bool}` for the current session |
| POST   | `login`     | none  | Body `{password}` → verifies against `ADMIN_PASSWORD_HASH` from `config.php` |
| POST   | `logout`    | none  | Destroys the session |
| POST   | `add`       | admin | Body `{brand, name, category, note?, uses}` → creates a new product, assigns `id` |
| PUT    | (none)      | admin | Body `{id, brand, name, category, note?, uses}` → updates an existing product |
| DELETE | (none)      | admin | Body `{id}` → removes a product |

Notes:
- `config.php` is git-ignored and must define `const ADMIN_PASSWORD_HASH = '...'`
  (bcrypt, produced via `password_hash(..., PASSWORD_BCRYPT)`).
- The public `GET` route intentionally runs **before** `session_start()`, so
  anonymous readers never get a `PHPSESSID` cookie. `session_start()` is only
  called for the auth-aware routes (`check`, `login`, `logout`, and write ops).
- `login` calls `session_regenerate_id(true)` on success to prevent session
  fixation.
- If `ADMIN_PASSWORD_HASH` is empty, `login` returns
  `503 "Password admin non impostata. Esegui setup.php."`. `setup.php` is a
  git-ignored one-shot helper — in production we set the hash manually (see
  `lxc/README.md` → "Modificare la password admin").
- Writes go through `writeProducts()` which uses `file_put_contents` with
  `JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES`. No
  locking — fine for the low-traffic, single-admin usage pattern.
- When running in production, `products.json` must be writable by the PHP-FPM
  user (e.g. `www-data:www-data` with `0664`).

## Deployment

The app runs inside a **non-privileged LXC container on Proxmox VE**
(Debian 13 Trixie + Nginx + PHP-FPM 8.4). The container was provisioned
manually — there are no bootstrap scripts in the repo. What lives in
[`lxc/`](lxc/) is documentation and one versioned config file:

- `lxc/README.md` — production snapshot + redeploy runbook + admin password
  management + troubleshooting
- `lxc/nginx-site.conf` — versioned copy of the Nginx site deployed at
  `/etc/nginx/sites-available/calcolo-diluizioni` (blocks `config.php`,
  `.env*`, dotfiles; `fastcgi_pass` to `/run/php/php-fpm.sock`)

The previous FTP-based deploy to activecloud (via GitHub Actions) has been
removed. If a change breaks production, **do not** restore the old FTP workflow;
diagnose the LXC container instead.

Production layout inside the container:

```
/var/www/calcolo-diluizioni/
├── diluizioni.html      # 0644 www-data:www-data
├── api.php              # 0644 www-data:www-data
├── products.json        # 0664 www-data:www-data (writable by PHP-FPM)
└── config.php           # 0640 root:www-data     (readable by PHP-FPM only)
```

Redeploy flow (inside the container, after a merge to `main`):

```bash
cd /tmp/diluition-calc && git fetch origin main && git reset --hard origin/main
install -m 0644 -o www-data -g www-data diluizioni.html /var/www/calcolo-diluizioni/diluizioni.html
install -m 0644 -o www-data -g www-data api.php        /var/www/calcolo-diluizioni/api.php
systemctl reload php8.4-fpm
```

See `lxc/README.md` for the full runbook.

## Testing

No automated tests exist. Manual testing procedure:
1. Run `php -S localhost:8000` from the repo root and open `http://localhost:8000/diluizioni.html`
2. Test each tab's functionality
3. Verify calculations with known values
4. Test edge cases (empty inputs, impossible dilutions)
5. Test on mobile viewport
6. If touching admin/API code: test login + add/edit/delete product flows

Example verification:
- 1L (1000ml) with ratio 1:10 should yield:
  - Product: 90.91 ml
  - Water: 909.09 ml

## Language

The application is entirely in **Italian**. Key terms:
- Calcolatore = Calculator
- Diluizione = Dilution
- Rapporto = Ratio
- Rabbocco = Refill
- Prodotto = Product
- Acqua = Water
- Flacone = Bottle
- Quantità = Quantity

## Browser Support

- Modern evergreen browsers (Chrome, Firefox, Safari, Edge)
- Mobile-responsive (viewport meta tag included)
- Requires JavaScript enabled

## Important Notes for AI Assistants

1. **Frontend in one file**: All frontend changes go in `diluizioni.html`
2. **Backend in one file**: All API changes go in `api.php`
3. **No build step**: Changes are immediately testable by refreshing the browser (after `php -S` in local dev)
4. **Italian language**: Maintain Italian for all user-facing text
5. **Keep it simple**: No external dependencies, no frameworks (on either frontend or backend)
6. **Mobile-first**: Test any UI changes at narrow viewport widths
7. **Preserve structure**: Keep CSS/HTML/JS sections in their current order in `diluizioni.html`
8. **Calculation accuracy**: Double-check math formulas — users rely on these for real measurements
9. **Products are dynamic**: Don't hardcode product data in the frontend; read from `GET /api.php`
10. **Never commit secrets**: `config.php` and `.env` are git-ignored and must stay that way

## Git Workflow

- `main` branch contains production code
- Feature branches for new development (commonly `claude/...` for AI-assisted work)
- Commit messages can be in Italian or English
- No automated CI/CD: redeploy is a manual `git fetch` + `install` + `systemctl reload php8.4-fpm`
  inside the LXC container (full runbook in [`lxc/README.md`](lxc/README.md))
- The old FTP-based GitHub Actions workflow has been removed — do not
  restore it if production breaks; diagnose the LXC container instead
