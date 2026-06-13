<?php

/**
 * CalorieLens local dev server — static host + real AI photo analysis.
 *
 * Run from mobile/:  php -S 127.0.0.1:8790 -t build/web webapi/server.php
 *
 * Serves the built Flutter app and exposes POST /api/analyze, which forwards
 * the photo to Claude vision with a forced tool call (the same structured-
 * output pattern as backend/app/Domain/AI/Providers/Vision/ClaudeVisionProvider
 * — this file is that provider in miniature, until the Laravel backend runs).
 *
 * The API key stays server-side: webapi/.env  →  ANTHROPIC_API_KEY=sk-ant-...
 */

declare(strict_types=1);

// ── Static files: let the built-in server handle anything that exists ──
$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH) ?: '/';
if (!in_array($path, ['/api/analyze', '/api/refine'], true)) {
    if ($path !== '/' && is_file($_SERVER['DOCUMENT_ROOT'] . $path)) {
        return false; // serve the asset as-is
    }
    // SPA fallback → index.html
    readfile($_SERVER['DOCUMENT_ROOT'] . '/index.html');
    return true;
}

// ── API routes ─────────────────────────────────────────────────────────
header('Content-Type: application/json');

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    echo json_encode(['error' => 'POST only']);
    return true;
}

// Shared-secret gate: with the tunnel up, this endpoint is on the public
// internet and every request costs Gemini quota. Browser-local (same-origin)
// use stays open; set APP_TOKEN in .env to require the header.
$expectedToken = envValue('APP_TOKEN');
if ($expectedToken !== null
    && !hash_equals($expectedToken, $_SERVER['HTTP_X_APP_TOKEN'] ?? '')) {
    http_response_code(401);
    echo json_encode(['error' => 'unauthorized', 'message' => 'Missing or wrong X-App-Token header.']);
    return true;
}

[$provider, $apiKey] = loadProvider();
if ($apiKey === null) {
    http_response_code(503);
    echo json_encode([
        'error' => 'no_api_key',
        'message' => 'Put ANTHROPIC_API_KEY=sk-ant-... or GEMINI_API_KEY=AIza... in mobile/webapi/.env and retry.',
    ]);
    return true;
}

$raw = file_get_contents('php://input', length: 20 * 1024 * 1024);
$body = json_decode($raw ?: '', true) ?: [];

if ($path === '/api/refine') {
    // User corrected one item ("air-fried chicken breast, not roasted") —
    // re-derive its nutrition from their description. User words win.
    $item = $body['item'] ?? null;
    $note = trim((string) ($body['note'] ?? ''));
    if (!is_array($item) || $note === '' || mb_strlen($note) > 500) {
        http_response_code(422);
        echo json_encode(['error' => 'invalid_request', 'message' => 'Body must be {"item": {...}, "note": "<1-500 chars>"}']);
        return true;
    }
    $result = $provider === 'gemini'
        ? callGeminiRefine($apiKey, $item, $note)
        : callClaudeRefine($apiKey, $item, $note);
    if (isset($result['error'])) {
        http_response_code(502);
        echo json_encode($result);
        return true;
    }
    $clean = validateAnalysis(['items' => [$result]])['items'][0] ?? null;
    if ($clean === null) {
        http_response_code(502);
        echo json_encode(['error' => 'empty_refinement', 'message' => 'Model returned no item.']);
        return true;
    }
    echo json_encode($clean, JSON_UNESCAPED_UNICODE);
    return true;
}

// /api/analyze
$imageB64 = $body['image'] ?? null;
$mediaType = $body['media_type'] ?? 'image/jpeg';
$userNote = trim((string) ($body['note'] ?? ''));

if (!is_string($imageB64) || base64_decode($imageB64, true) === false) {
    http_response_code(422);
    echo json_encode(['error' => 'invalid_image', 'message' => 'Body must be {"image": <base64>, "media_type": "image/jpeg"}']);
    return true;
}
if (!in_array($mediaType, ['image/jpeg', 'image/png', 'image/webp', 'image/gif'], true)) {
    $mediaType = 'image/jpeg';
}

$result = $provider === 'gemini'
    ? callGeminiVision($apiKey, $imageB64, $mediaType, $userNote)
    : callClaudeVision($apiKey, $imageB64, $mediaType, $userNote);
if (isset($result['error'])) {
    http_response_code(502);
    echo json_encode($result);
    return true;
}

echo json_encode(validateAnalysis($result), JSON_UNESCAPED_UNICODE);
return true;

// ───────────────────────────────────────────────────────────────────────

/** getenv() with webapi/.env fallback. */
function envValue(string $name): ?string
{
    static $env = null;
    if ($env === null) {
        $env = [];
        $envFile = __DIR__ . '/.env';
        if (is_file($envFile)) {
            foreach (file($envFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
                $line = trim($line);
                if ($line === '' || str_starts_with($line, '#') || !str_contains($line, '=')) {
                    continue;
                }
                [$key, $value] = explode('=', $line, 2);
                $env[trim($key)] = trim($value, " \t\"'");
            }
        }
    }
    return getenv($name) ?: ($env[$name] ?? null);
}

/**
 * Returns [provider, key]. Reads webapi/.env (and real env vars); uses
 * whichever key is present. If both are set, CALORIELENS_PROVIDER
 * (anthropic|gemini) picks; default prefers gemini (free tier).
 */
function loadProvider(): array
{
    $get = fn (string $name): ?string => envValue($name);

    $anthropic = $get('ANTHROPIC_API_KEY');
    if ($anthropic !== null && !str_starts_with($anthropic, 'sk-ant-')) {
        $anthropic = null;
    }
    $gemini = $get('GEMINI_API_KEY') ?? $get('GOOGLE_API_KEY');
    if ($gemini !== null && strlen($gemini) < 20) {
        $gemini = null;
    }

    $preference = strtolower($get('CALORIELENS_PROVIDER') ?? '');
    if ($preference === 'anthropic' && $anthropic !== null) {
        return ['anthropic', $anthropic];
    }
    if ($preference === 'gemini' && $gemini !== null) {
        return ['gemini', $gemini];
    }
    if ($gemini !== null) {
        return ['gemini', $gemini];
    }
    if ($anthropic !== null) {
        return ['anthropic', $anthropic];
    }
    return ['none', null];
}

/** Shared JSON POST. Returns [status|null, decoded|null, curlError]. */
function httpPostJson(string $url, array $headers, array $payload): array
{
    $ch = curl_init($url);
    curl_setopt_array($ch, [
        CURLOPT_POST => true,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 90,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_POSTFIELDS => json_encode($payload),
    ]);
    $response = curl_exec($ch);
    $status = curl_getinfo($ch, CURLINFO_RESPONSE_CODE);
    $curlErr = curl_error($ch);
    curl_close($ch);

    if ($response === false) {
        return [null, null, $curlErr];
    }
    return [$status, json_decode($response, true), ''];
}

function userTextWithNote(string $userNote): string
{
    $text = 'Analyze this meal photo and report every food item.';
    if ($userNote !== '') {
        // The eater knows their food: their description overrides visual
        // assumptions (preparation, ingredients, sweetness, oil).
        $text .= "\n\nThe user added context about this meal — TRUST IT over your visual assumptions: \"" . $userNote . '"';
    }
    return $text;
}

function callClaudeVision(string $apiKey, string $imageB64, string $mediaType, string $userNote = ''): array
{
    $payload = [
        'model' => envValue('CALORIELENS_MODEL') ?: 'claude-sonnet-4-6',
        'max_tokens' => 3000,
        'system' => visionSystemPrompt(),
        'messages' => [[
            'role' => 'user',
            'content' => [
                ['type' => 'image', 'source' => ['type' => 'base64', 'media_type' => $mediaType, 'data' => $imageB64]],
                ['type' => 'text', 'text' => userTextWithNote($userNote)],
            ],
        ]],
        'tools' => [analysisToolSchema()],
        'tool_choice' => ['type' => 'tool', 'name' => 'report_food_analysis'],
    ];

    [$status, $decoded, $curlErr] = httpPostJson('https://api.anthropic.com/v1/messages', [
        'x-api-key: ' . $apiKey,
        'anthropic-version: 2023-06-01',
        'content-type: application/json',
    ], $payload);

    if ($status === null) {
        return ['error' => 'provider_unreachable', 'message' => $curlErr];
    }
    if ($status !== 200) {
        return [
            'error' => 'provider_error',
            'message' => $decoded['error']['message'] ?? "HTTP $status from Anthropic",
        ];
    }
    foreach ($decoded['content'] ?? [] as $block) {
        if (($block['type'] ?? '') === 'tool_use' && ($block['name'] ?? '') === 'report_food_analysis') {
            return $block['input'];
        }
    }
    return ['error' => 'no_tool_call', 'message' => 'Model did not return a structured analysis.'];
}

function callClaudeRefine(string $apiKey, array $item, string $note): array
{
    $payload = [
        'model' => envValue('CALORIELENS_MODEL') ?: 'claude-sonnet-4-6',
        'max_tokens' => 1200,
        'system' => refineSystemPrompt(),
        'messages' => [[
            'role' => 'user',
            'content' => [[
                'type' => 'text',
                'text' => refineUserText($item, $note),
            ]],
        ]],
        'tools' => [[
            'name' => 'report_food_item',
            'description' => 'Report the corrected food item.',
            'input_schema' => itemSchema(),
        ]],
        'tool_choice' => ['type' => 'tool', 'name' => 'report_food_item'],
    ];

    [$status, $decoded, $curlErr] = httpPostJson('https://api.anthropic.com/v1/messages', [
        'x-api-key: ' . $apiKey,
        'anthropic-version: 2023-06-01',
        'content-type: application/json',
    ], $payload);

    if ($status === null) {
        return ['error' => 'provider_unreachable', 'message' => $curlErr];
    }
    if ($status !== 200) {
        return ['error' => 'provider_error', 'message' => $decoded['error']['message'] ?? "HTTP $status from Anthropic"];
    }
    foreach ($decoded['content'] ?? [] as $block) {
        if (($block['type'] ?? '') === 'tool_use' && ($block['name'] ?? '') === 'report_food_item') {
            return $block['input'];
        }
    }
    return ['error' => 'no_tool_call', 'message' => 'Model did not return a corrected item.'];
}

function callGeminiVision(string $apiKey, string $imageB64, string $mediaType, string $userNote = ''): array
{
    // Same canonical prompt; structured output via responseSchema instead of
    // a forced tool call (mirrors backend GeminiVisionProvider).
    $payload = [
        'systemInstruction' => ['parts' => [['text' => visionSystemPrompt()]]],
        'contents' => [[
            'role' => 'user',
            'parts' => [
                ['inlineData' => ['mimeType' => $mediaType, 'data' => $imageB64]],
                ['text' => userTextWithNote($userNote)],
            ],
        ]],
        'generationConfig' => [
            'responseMimeType' => 'application/json',
            'responseSchema' => toGeminiSchema(analysisToolSchema()['input_schema']),
            'maxOutputTokens' => 8192,
        ],
    ];

    // Vision uses the stronger model for accuracy, falling back to the
    // higher-quota lite model only if the daily limit is hit.
    return geminiGenerate($apiKey, $payload, visionModelChain());
}

function callGeminiRefine(string $apiKey, array $item, string $note): array
{
    $payload = [
        'systemInstruction' => ['parts' => [['text' => refineSystemPrompt()]]],
        'contents' => [[
            'role' => 'user',
            'parts' => [['text' => refineUserText($item, $note)]],
        ]],
        'generationConfig' => [
            'responseMimeType' => 'application/json',
            'responseSchema' => toGeminiSchema(itemSchema()),
            'maxOutputTokens' => 2048,
        ],
    ];

    // Text correction is easy — the cheap model is fine.
    return geminiGenerate($apiKey, $payload, [envValue('CALORIELENS_MODEL') ?: 'gemini-2.5-flash-lite']);
}

/**
 * Photo analysis prefers the stronger model (much better at portion/depth
 * judgement) and degrades to lite only when quota is exhausted — best
 * accuracy while the daily allowance lasts, still working after.
 */
function visionModelChain(): array
{
    $primary = envValue('CALORIELENS_VISION_MODEL') ?: 'gemini-2.5-flash';
    $models = [$primary];
    if (!str_contains($primary, 'lite')) {
        $models[] = 'gemini-2.5-flash-lite';
    }
    return $models;
}

/**
 * Try each model in order. Transient 429/503 → one in-place retry; a real
 * quota wall → fall through to the next (cheaper) model; only when every
 * model is exhausted do we report quota_exceeded.
 *
 * @param array<int,string> $models
 */
function geminiGenerate(string $apiKey, array $payload, array $models): array
{
    $headers = ['x-goog-api-key: ' . $apiKey, 'content-type: application/json'];
    $last = ['error' => 'provider_error', 'message' => 'No model attempted.'];

    foreach (array_values($models) as $i => $model) {
        $url = "https://generativelanguage.googleapis.com/v1beta/models/{$model}:generateContent";

        [$status, $decoded, $curlErr] = httpPostJson($url, $headers, $payload);
        if ($status === 429 || $status === 503) {
            sleep(2);
            [$status, $decoded, $curlErr] = httpPostJson($url, $headers, $payload);
        }

        if ($status === null) {
            $last = ['error' => 'provider_unreachable', 'message' => $curlErr];
            continue;
        }
        if ($status === 200) {
            $text = $decoded['candidates'][0]['content']['parts'][0]['text'] ?? null;
            $analysis = is_string($text) ? json_decode($text, true) : null;
            if (is_array($analysis)) {
                return $analysis;
            }
            $last = ['error' => 'no_structured_output', 'message' => 'Gemini did not return parseable JSON.'];
            continue;
        }

        $msg = $decoded['error']['message'] ?? "HTTP $status from Gemini";
        $isQuota = $status === 429 || stripos($msg, 'quota') !== false
            || stripos($msg, 'RESOURCE_EXHAUSTED') !== false;
        if ($isQuota && $i < count($models) - 1) {
            continue; // try the next, higher-quota model
        }
        if ($isQuota) {
            return [
                'error' => 'quota_exceeded',
                'message' => 'Daily AI limit reached — resets midnight Pacific (~3-4pm MYT), or enable billing.',
            ];
        }
        $last = ['error' => 'provider_error', 'message' => $msg];
    }
    return $last;
}

/**
 * Gemini's responseSchema is a JSON Schema subset: no "required" arrays with
 * unknown props quirks are fine, but minimum/maximum must be dropped.
 */
function toGeminiSchema(array $schema): array
{
    unset($schema['minimum'], $schema['maximum'], $schema['description']);
    foreach (['properties', 'items'] as $key) {
        if (isset($schema[$key])) {
            if ($key === 'items') {
                $schema['items'] = toGeminiSchema($schema['items']);
            } else {
                foreach ($schema['properties'] as $name => $child) {
                    $schema['properties'][$name] = toGeminiSchema($child);
                }
            }
        }
    }
    return $schema;
}

/**
 * Trimmed dev edition of FoodVisionPrompt (VERSION 2026-06-01.1) — same
 * decomposition rules, calibration bands, and honesty contract.
 */
function visionSystemPrompt(): string
{
    return <<<'PROMPT'
You are the food recognition engine of CalorieLens, a calorie tracking app used heavily in Malaysia and Singapore. Your hardest job is PORTION SIZE — identity is usually easy, but weight estimated from a flat photo is where calorie error comes from. Work it carefully.

Identify every distinct food and drink. Rules:

1. DECOMPOSE mixed dishes into components. Nasi lemak is never one item — it is coconut rice, sambal, fried egg, ikan bilis, peanuts, cucumber, plus any protein, each estimated separately. Same for chicken rice, mixed rice (nasi campur), burgers with sides, etc. A plain single food (an apple, black coffee) stays one item.

2. PORTION METHOD — for each item, reason in this order before giving grams:
   a. SCALE: find the size reference. Best is a known object in frame — fork ≈ 19 cm, dinner spoon ≈ 15 cm, teaspoon ≈ 11 cm, chopsticks ≈ 24 cm, credit card 85.6 × 54 mm, an adult hand ≈ 18 cm. Else use the plate/bowl rim (dinner plate ≈ 26 cm, rice bowl rim ≈ 11 cm, mug ≈ 8 cm). State which reference you used.
   b. AREA × DEPTH: judge how much of the plate the food covers AND its height/mound — a thick pile weighs far more than a thin layer of the same footprint. Deep bowls hide volume; lean larger.
   c. DENSITY: rice/noodles ≈ 1.0 g/ml cooked, soups/broth light, fried items lighter but oil-laden, meat dense.
   d. COUNTABLES: when you can count units (eggs, satay sticks, prawns, slices, dumplings), count them × typical unit weight — far more reliable than area.
   Give grams_low/grams_high as an honest 80% interval: tight when you have a clear scale reference and countable units, WIDE when no reference object, deep bowl, heavy sauce, or stacked/overlapping food. For bone-in items estimate edible flesh only.

3. HIDDEN CALORIES — the biggest source of underestimation. Actively account for what the photo hides:
   - COOKING OIL/FAT: anything fried, stir-fried, or glossy (char kuey teow, nasi goreng, fried rice, mee goreng) carries 10–25 g of absorbed oil/lard not obviously visible. Bake it into that item's fat, OR add a small separate "Cooking oil" item when a dish is clearly oily.
   - SUGAR in drinks & sauces: kopi/teh/milo default to sweetened with condensed/evaporated milk + sugar unless the user says kosong/kurang manis or it visibly isn't. Sweet sauces (sambal, sweet soy, chilli) carry sugar.
   - COCONUT MILK / GHEE / BUTTER: santan in curries and rice, butter on toast, ghee on roti — add their fat.
   - DRESSINGS/GRAVY ladled over rice.

4. CONFIDENCE, calibrated and HONEST: 0.9+ only when identity AND portion are both clear (clear scale reference or countable units); 0.7–0.89 when identity is clear but portion is uncertain (no scale reference, deep bowl); below 0.7 when guessing identity or much is hidden. Never inflate — a low score is what tells the user to check.

5. REASONING: 1–2 sentences to the user stating the scale reference used, the area/depth read, and any hidden-calorie assumption ("Used the fork for scale; rice covers ~⅓ of the plate, ~2 cm deep; counted absorbed oil from the wok sheen").

6. NUTRITION per 100 g AS PREPARED. Calories must satisfy Atwater: kcal ≈ 4×protein + 4×carbs + 9×fat, within ~15%.

7. DRINKS: is_drink true (the app credits hydration). Everything else false. Sauces/dressings count as food. Garnish under 5 g may be ignored.

8. If no food in the photo, return zero items and say so in overall_note.

9. overall_note: one sentence naming the dish and the single biggest source of uncertainty (usually a portion or hidden-fat call).

Be honest over impressive. An accurate range beats a precise-looking wrong number.
PROMPT;
}

function refineSystemPrompt(): string
{
    return <<<'PROMPT'
You correct a single food item from a CalorieLens meal-photo analysis using the user's own description of what they actually ate. The user knows their food better than any image — their words OVERRIDE the original visual identification for identity, preparation method, and ingredients (e.g. "air-fried chicken breast, no skin" replaces "roasted chicken piece"; "milo kosong" means no condensed milk and no added sugar).

Rules:
1. Recompute per-100g nutrition for the corrected item AS PREPARED. Air-fried ≈ minimal added oil; deep-fried includes absorbed oil; kosong drinks drop condensed milk and sugar.
2. Keep the portion (grams and range) from the original UNLESS the correction implies a different amount ("it was two eggs", "large bowl").
3. Update the label to the corrected food, written cleanly ("Air-fried Chicken Breast", not the user's raw text).
4. reasoning: 1–2 sentences acknowledging the correction and what changed nutritionally.
5. confidence reflects remaining uncertainty AFTER the correction — identity from the user is near-certain, so typically 0.9+ unless the portion is still a guess.
6. Calories must satisfy Atwater: kcal ≈ 4×protein + 4×carbs + 9×fat within ~15%.
PROMPT;
}

function refineUserText(array $item, string $note): string
{
    return "Original item from the photo analysis:\n"
        . json_encode($item, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)
        . "\n\nUser correction: \"{$note}\"\n\nReturn the corrected item.";
}

function itemSchema(): array
{
    $per100g = [
        'type' => 'object',
        'properties' => [
            'kcal' => ['type' => 'number'],
            'protein_g' => ['type' => 'number'],
            'carbs_g' => ['type' => 'number'],
            'fat_g' => ['type' => 'number'],
            'fiber_g' => ['type' => 'number'],
            'sugar_g' => ['type' => 'number'],
            'sodium_mg' => ['type' => 'number'],
        ],
        'required' => ['kcal', 'protein_g', 'carbs_g', 'fat_g'],
    ];

    return [
        'type' => 'object',
        'properties' => [
            'label' => ['type' => 'string'],
            'emoji' => ['type' => 'string', 'description' => 'Single emoji for the item'],
            'grams' => ['type' => 'number'],
            'grams_low' => ['type' => 'number'],
            'grams_high' => ['type' => 'number'],
            'confidence' => ['type' => 'number', 'minimum' => 0, 'maximum' => 1],
            'reasoning' => ['type' => 'string'],
            'is_drink' => ['type' => 'boolean', 'description' => 'true for beverages (counts toward hydration)'],
            'per_100g' => $per100g,
        ],
        'required' => ['label', 'grams', 'grams_low', 'grams_high', 'confidence', 'reasoning', 'is_drink', 'per_100g'],
    ];
}

function analysisToolSchema(): array
{
    return [
        'name' => 'report_food_analysis',
        'description' => 'Report the structured analysis of a meal photo.',
        'input_schema' => [
            'type' => 'object',
            'properties' => [
                'dish_name' => ['type' => 'string', 'description' => 'Short name for the whole meal, e.g. "Nasi Lemak"'],
                'overall_note' => ['type' => 'string'],
                'items' => ['type' => 'array', 'items' => itemSchema()],
            ],
            'required' => ['dish_name', 'overall_note', 'items'],
        ],
    ];
}

/**
 * Mini NutritionValidator: clamp ranges, fix inverted bounds, and repair
 * Atwater-inconsistent calories (catches kJ-as-kcal style errors).
 */
function validateAnalysis(array $analysis): array
{
    $items = [];
    foreach ($analysis['items'] ?? [] as $item) {
        $grams = max(1.0, (float) ($item['grams'] ?? 0));
        $low = (float) ($item['grams_low'] ?? $grams * 0.8);
        $high = (float) ($item['grams_high'] ?? $grams * 1.25);
        if ($low > $high) {
            [$low, $high] = [$high, $low];
        }
        $low = min($low, $grams);
        $high = max($high, $grams);

        $n = $item['per_100g'] ?? [];
        $protein = max(0.0, (float) ($n['protein_g'] ?? 0));
        $carbs = max(0.0, (float) ($n['carbs_g'] ?? 0));
        $fat = max(0.0, (float) ($n['fat_g'] ?? 0));
        $kcal = (float) ($n['kcal'] ?? 0);
        $atwater = 4 * $protein + 4 * $carbs + 9 * $fat;
        if ($atwater > 0 && abs($kcal - $atwater) / $atwater > 0.35) {
            $kcal = $atwater; // model arithmetic slipped — trust the macros
        }

        $items[] = [
            'label' => (string) ($item['label'] ?? 'Unknown food'),
            'emoji' => (string) ($item['emoji'] ?? '🍽️'),
            'grams' => round($grams, 1),
            'grams_low' => round($low, 1),
            'grams_high' => round($high, 1),
            'confidence' => min(1.0, max(0.0, (float) ($item['confidence'] ?? 0.5))),
            'reasoning' => (string) ($item['reasoning'] ?? ''),
            'is_drink' => (bool) ($item['is_drink'] ?? false),
            'per_100g' => [
                'kcal' => round($kcal, 1),
                'protein_g' => round($protein, 2),
                'carbs_g' => round($carbs, 2),
                'fat_g' => round($fat, 2),
                'fiber_g' => round(max(0.0, (float) ($n['fiber_g'] ?? 0)), 2),
                'sugar_g' => round(max(0.0, (float) ($n['sugar_g'] ?? 0)), 2),
                'sodium_mg' => round(max(0.0, (float) ($n['sodium_mg'] ?? 0)), 1),
            ],
        ];
    }

    return [
        'dish_name' => (string) ($analysis['dish_name'] ?? 'Meal'),
        'overall_note' => (string) ($analysis['overall_note'] ?? ''),
        'items' => $items,
    ];
}
