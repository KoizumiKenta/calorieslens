<?php

namespace App\Services\Food;

use App\Support\Atwater;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * The "any food" escape hatch. When the curated seed and Open Food Facts both
 * come up short — common for local hawker dishes like ban mee, loh mee, or
 * wantan mee that no Western database carries — Gemini estimates the nutrition
 * from the dish name. Output is Atwater-reconciled and flagged source='ai'
 * (unverified) so the UI can show it as an estimate, not gospel.
 */
class AiEstimateSource
{
    public function estimate(string $name): ?array
    {
        $key = config('calorielens.gemini_key');
        if (! $key) {
            return null;
        }
        $model = config('calorielens.text_model');
        $url = "https://generativelanguage.googleapis.com/v1beta/models/{$model}:generateContent";

        try {
            $res = Http::timeout(30)->withHeaders(['x-goog-api-key' => $key])->post($url, [
                'systemInstruction' => ['parts' => [['text' => $this->systemPrompt()]]],
                'contents' => [[
                    'role' => 'user',
                    'parts' => [['text' => "Estimate the nutrition for: \"{$name}\""]],
                ]],
                'generationConfig' => [
                    'responseMimeType' => 'application/json',
                    'responseSchema' => $this->schema(),
                    'maxOutputTokens' => 1024,
                    'temperature' => 0.2,
                ],
            ]);
            if (! $res->ok()) {
                Log::warning('AI estimate failed', ['name' => $name, 'status' => $res->status()]);
                return null;
            }
            $text = $res->json('candidates.0.content.parts.0.text');
            $data = is_string($text) ? json_decode($text, true) : null;
            if (! is_array($data)) {
                return null;
            }
            return $this->normalize($name, $data);
        } catch (\Throwable $e) {
            Log::warning('AI estimate error', ['name' => $name, 'e' => $e->getMessage()]);
            return null;
        }
    }

    private function normalize(string $query, array $d): ?array
    {
        $n = $d['per_100g'] ?? [];
        $protein = max(0.0, (float) ($n['protein_g'] ?? 0));
        $carbs = max(0.0, (float) ($n['carbs_g'] ?? 0));
        $fat = max(0.0, (float) ($n['fat_g'] ?? 0));
        $kcal = Atwater::reconcile((float) ($n['kcal'] ?? 0), $protein, $carbs, $fat);
        if (! Atwater::isPlausible($kcal, $protein, $carbs, $fat)) {
            return null;
        }

        $isDrink = (bool) ($d['is_drink'] ?? false);
        $portions = [];
        foreach (($d['portions'] ?? []) as $p) {
            $g = (float) ($p['grams'] ?? 0);
            if ($g > 0 && $g < 2000 && ! empty($p['label'])) {
                $portions[] = ['label' => (string) $p['label'], 'grams' => round($g, 1)];
            }
        }

        return [
            'source' => 'ai',
            'external_id' => \Illuminate\Support\Str::slug($query),
            'name' => mb_substr(trim((string) ($d['name'] ?? $query)), 0, 120),
            'brand' => null,
            'region' => in_array($d['region'] ?? null, ['MY', 'SG', 'ID', 'TH'], true) ? $d['region'] : null,
            'emoji' => (string) ($d['emoji'] ?? '🍽️'),
            'kcal' => round($kcal, 1),
            'protein_g' => round($protein, 2),
            'carbs_g' => round($carbs, 2),
            'fat_g' => round($fat, 2),
            'fiber_g' => round(max(0.0, (float) ($n['fiber_g'] ?? 0)), 2),
            'sugar_g' => round(max(0.0, (float) ($n['sugar_g'] ?? 0)), 2),
            'sodium_mg' => round(max(0.0, (float) ($n['sodium_mg'] ?? 0)), 1),
            'portions' => $portions,
            'aliases' => array_values(array_filter(array_map(
                fn ($a) => is_string($a) ? mb_substr($a, 0, 60) : null,
                $d['aliases'] ?? [],
            ))),
            'hydration_factor' => $isDrink ? 0.88 : null,
            'verified' => false,
        ];
    }

    private function systemPrompt(): string
    {
        return <<<'PROMPT'
You are the nutrition estimator for CalorieLens, used heavily in Malaysia and Singapore. Given a food or dish name, return your best per-100g nutrition estimate for it AS TYPICALLY PREPARED AND SERVED locally.

Rules:
- Know local hawker and home dishes: ban mee (pan mee), wantan mee, loh mee, char kuey teow, mee rebus, lor bak, chee cheong fun, economy rice dishes, kopitiam drinks, etc. Estimate realistically including cooking oil, lard, santan, sugar, and sauces where typical.
- per_100g must be calorie-consistent: kcal ≈ 4*protein_g + 4*carbs_g + 9*fat_g.
- portions: give 1–2 realistic serving sizes in grams (e.g. "1 bowl" 500 g, "1 plate" 350 g). A drink's serving is its volume in ml ≈ grams.
- region: "MY", "SG", "ID", or "TH" only if it is clearly that regional dish; otherwise null.
- is_drink: true for beverages.
- emoji: one fitting emoji.
- aliases: common alternate names/spellings (e.g. "pan mee" for ban mee).
- Estimate honestly. A reasonable range is better than false precision, but commit to a single best per-100g number.
PROMPT;
    }

    private function schema(): array
    {
        return [
            'type' => 'object',
            'properties' => [
                'name' => ['type' => 'string'],
                'emoji' => ['type' => 'string'],
                'region' => ['type' => 'string', 'nullable' => true],
                'is_drink' => ['type' => 'boolean'],
                'per_100g' => [
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
                ],
                'portions' => [
                    'type' => 'array',
                    'items' => [
                        'type' => 'object',
                        'properties' => [
                            'label' => ['type' => 'string'],
                            'grams' => ['type' => 'number'],
                        ],
                        'required' => ['label', 'grams'],
                    ],
                ],
                'aliases' => ['type' => 'array', 'items' => ['type' => 'string']],
            ],
            'required' => ['name', 'emoji', 'is_drink', 'per_100g', 'portions'],
        ];
    }
}
