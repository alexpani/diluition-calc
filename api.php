<?php
session_start();
require_once __DIR__ . '/config.php';

header('Content-Type: application/json; charset=utf-8');

$method = $_SERVER['REQUEST_METHOD'];
$action = $_GET['action'] ?? '';
$productsFile = __DIR__ . '/products.json';

// --- Helpers ---

function readProducts(string $file): array {
    if (!file_exists($file)) return [];
    $data = json_decode(file_get_contents($file), true);
    return is_array($data) ? $data : [];
}

function writeProducts(string $file, array $products): bool {
    $json = json_encode($products, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    return file_put_contents($file, $json) !== false;
}

function isAuthenticated(): bool {
    return isset($_SESSION['admin']) && $_SESSION['admin'] === true;
}

function requireAuth(): void {
    if (!isAuthenticated()) {
        http_response_code(401);
        echo json_encode(['error' => 'Non autorizzato']);
        exit;
    }
}

function getBody(): array {
    $raw = file_get_contents('php://input');
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

function respond(array $data, int $code = 200): void {
    http_response_code($code);
    echo json_encode($data);
    exit;
}

function respondError(string $message, int $code = 400): void {
    http_response_code($code);
    echo json_encode(['error' => $message]);
    exit;
}

// --- Routes ---

// GET / — lista prodotti (pubblica)
if ($method === 'GET' && $action === '') {
    echo file_get_contents($productsFile) ?: '[]';
    exit;
}

// GET ?action=check — verifica sessione admin
if ($method === 'GET' && $action === 'check') {
    respond(['authenticated' => isAuthenticated()]);
}

// POST ?action=login
if ($method === 'POST' && $action === 'login') {
    $body = getBody();
    $password = $body['password'] ?? '';

    if (ADMIN_PASSWORD_HASH === '') {
        respondError('Password admin non impostata. Esegui setup.php.', 503);
    }

    if (!password_verify($password, ADMIN_PASSWORD_HASH)) {
        respondError('Password errata', 401);
    }

    $_SESSION['admin'] = true;
    respond(['success' => true]);
}

// POST ?action=logout
if ($method === 'POST' && $action === 'logout') {
    session_destroy();
    respond(['success' => true]);
}

// POST ?action=add — aggiunge un prodotto
if ($method === 'POST' && $action === 'add') {
    requireAuth();
    $body = getBody();

    if (empty($body['brand']) || empty($body['name']) || empty($body['category'])) {
        respondError('Marchio, nome e categoria sono obbligatori');
    }

    $products = readProducts($productsFile);

    $maxId = 0;
    foreach ($products as $p) {
        if (($p['id'] ?? 0) > $maxId) $maxId = $p['id'];
    }

    $product = [
        'id'       => $maxId + 1,
        'brand'    => trim($body['brand']),
        'name'     => trim($body['name']),
        'category' => trim($body['category']),
        'note'     => !empty($body['note']) ? trim($body['note']) : null,
        'uses'     => $body['uses'] ?? [],
    ];

    $products[] = $product;

    if (!writeProducts($productsFile, $products)) {
        respondError('Errore durante il salvataggio', 500);
    }

    respond($product, 201);
}

// PUT — aggiorna un prodotto esistente
if ($method === 'PUT') {
    requireAuth();
    $body = getBody();

    $id = $body['id'] ?? null;
    if (!$id) respondError('ID mancante');

    if (empty($body['brand']) || empty($body['name']) || empty($body['category'])) {
        respondError('Marchio, nome e categoria sono obbligatori');
    }

    $products = readProducts($productsFile);
    $found = false;

    foreach ($products as &$p) {
        if (($p['id'] ?? null) == $id) {
            $p = [
                'id'       => (int)$id,
                'brand'    => trim($body['brand']),
                'name'     => trim($body['name']),
                'category' => trim($body['category']),
                'note'     => !empty($body['note']) ? trim($body['note']) : null,
                'uses'     => $body['uses'] ?? [],
            ];
            $found = true;
            break;
        }
    }
    unset($p);

    if (!$found) respondError('Prodotto non trovato', 404);

    if (!writeProducts($productsFile, $products)) {
        respondError('Errore durante il salvataggio', 500);
    }

    respond(['success' => true]);
}

// DELETE — elimina un prodotto
if ($method === 'DELETE') {
    requireAuth();
    $body = getBody();

    $id = $body['id'] ?? null;
    if (!$id) respondError('ID mancante');

    $products = readProducts($productsFile);
    $before = count($products);
    $products = array_values(array_filter($products, fn($p) => ($p['id'] ?? null) != $id));

    if (count($products) === $before) {
        respondError('Prodotto non trovato', 404);
    }

    if (!writeProducts($productsFile, $products)) {
        respondError('Errore durante il salvataggio', 500);
    }

    respond(['success' => true]);
}

http_response_code(404);
echo json_encode(['error' => 'Azione non trovata']);
