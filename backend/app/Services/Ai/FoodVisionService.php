<?php

namespace App\Services\Ai;

use App\Support\Atwater;

/**
 * Photo → structured meal analysis, and single-item correction. Ported from
 * the dev php-proxy (mobile/webapi/server.php) into the backend so there is
 * one API origin. The prompt is portion-method-first with a hidden-calorie
 * checklist; every number is Atwater-reconciled before it leaves here.
 */
class FoodVisionService
{
    public function __construct(private readonly GeminiClient $gemini) {}

    /** @return array<string,mixed> validated analysis, or ['error' => ...] */
    public function analyze(string $imageB64, string $mediaType, string $note = ''): array
    {
        $payload = [
            'systemInstruction' => ['parts' => [['text' => $this->visionPrompt()]]],
            'contents' => [[
                'role' => 'user',
                'parts' => [
                    ['inlineData' => ['mimeType' => $mediaType, 'data' => $imageB64]],
                    ['text' => $this->userText($note)],
                ],
            ]],
            'generationConfig' => [
                'responseMimeType' => 'application/json',
                'responseSchema' => GeminiClient::toGeminiSchema($this->analysisSchema()),
                'maxOutputTokens' => 8192,
            ],
        ];

        $raw = $this->gemini->generate($payload, GeminiClient::visionModels());
        if (isset($raw['error'])) {
            return $raw;
        }

        return [
            'dish_name' => (string) ($raw['dish_name'] ?? 'Meal'),
            'overall_note' => (string) ($raw['overall_note'] ?? ''),
            'items' => array_map(fn ($i) => $this->cleanItem($i), $raw['items'] ?? []),
        ];
    }

    /** @return array<string,mixed> one validated item, or ['error' => ...] */
    public function refine(array $item, string $note): array
    {
        $payload = [
            'systemInstruction' => ['parts' => [['text' => $this->refinePrompt()]]],
            'contents' => [[
                'role' => 'user',
                'parts' => [['text' => "Original item:\n".json_encode($item, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)."\n\nUser correction: \"{$note}\"\n\nReturn the corrected item."]],
            ]],
            'generationConfig' => [
                'responseMimeType' => 'application/json',
                'responseSchema' => GeminiClient::toGeminiSchema($this->itemSchema()),
                'maxOutputTokens' => 2048,
            ],
        ];

        // Correction is text-only — the cheap model is fine.
        $raw = $this->gemini->generate($payload, [config('calorielens.text_model')]);
        if (isset($raw['error'])) {
            return $raw;
        }

        return $this->cleanItem($raw);
    }

    private function userText(string $note): string
    {
        $text = 'Analyze this meal photo and report every food item.';
        if (trim($note) !== '') {
            $text .= "\n\nThe user added context about this meal — TRUST IT over your visual assumptions: \"".trim($note).'"';
        }

        return $text;
    }

    /** Atwater-reconcile and clamp one model item into our canonical shape. */
    private function cleanItem(array $item): array
    {
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
        $kcal = Atwater::reconcile((float) ($n['kcal'] ?? 0), $protein, $carbs, $fat);

        return [
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

    private function analysisSchema(): array
    {
        return [
            'type' => 'object',
            'properties' => [
                'dish_name' => ['type' => 'string'],
                'overall_note' => ['type' => 'string'],
                'items' => ['type' => 'array', 'items' => $this->itemSchema()],
            ],
            'required' => ['dish_name', 'overall_note', 'items'],
        ];
    }

    private function itemSchema(): array
    {
        return [
            'type' => 'object',
            'properties' => [
                'label' => ['type' => 'string'],
                'emoji' => ['type' => 'string'],
                'grams' => ['type' => 'number'],
                'grams_low' => ['type' => 'number'],
                'grams_high' => ['type' => 'number'],
                'confidence' => ['type' => 'number'],
                'reasoning' => ['type' => 'string'],
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
            ],
            'required' => ['label', 'grams', 'grams_low', 'grams_high', 'confidence', 'reasoning', 'is_drink', 'per_100g'],
        ];
    }

    private function visionPrompt(): string
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
   - SUGAR in drinks & sauces: kopi/teh/milo default to sweetened with condensed/evaporated milk + sugar unless the user says kosong/kurang manis or it visibly isn't. Sweet sauces carry sugar.
   - COCONUT MILK / GHEE / BUTTER: santan in curries and rice, butter on toast, ghee on roti — add their fat.
   - DRESSINGS/GRAVY ladled over rice.

4. CONFIDENCE, calibrated and HONEST: 0.9+ only when identity AND portion are both clear (clear scale reference or countable units); 0.7–0.89 when identity is clear but portion is uncertain; below 0.7 when guessing identity or much is hidden. Never inflate — a low score is what tells the user to check.

5. REASONING: 1–2 sentences to the user stating the scale reference used, the area/depth read, and any hidden-calorie assumption.

6. NUTRITION per 100 g AS PREPARED. Calories must satisfy Atwater: kcal ≈ 4×protein + 4×carbs + 9×fat, within ~15%.

7. DRINKS: is_drink true (the app credits hydration). Everything else false. Sauces/dressings count as food. Garnish under 5 g may be ignored.

8. If no food in the photo, return zero items and say so in overall_note.

9. overall_note: one sentence naming the dish and the single biggest source of uncertainty.

Be honest over impressive. An accurate range beats a precise-looking wrong number.
PROMPT;
    }

    private function refinePrompt(): string
    {
        return <<<'PROMPT'
You correct a single food item from a CalorieLens meal-photo analysis using the user's own description of what they actually ate. The user knows their food better than any image — their words OVERRIDE the original visual identification for identity, preparation, and ingredients (e.g. "air-fried chicken breast, no skin" replaces "roasted chicken"; "milo kosong" means no condensed milk and no sugar).

Rules:
1. Recompute per-100g nutrition AS PREPARED. Air-fried ≈ minimal oil; deep-fried includes absorbed oil; kosong drinks drop condensed milk and sugar.
2. Keep the portion (grams and range) from the original UNLESS the correction implies a different amount.
3. Update the label cleanly. reasoning: 1–2 sentences on what changed.
4. confidence reflects remaining uncertainty after the correction — usually 0.9+.
5. Calories must satisfy Atwater: kcal ≈ 4×protein + 4×carbs + 9×fat.
6. Set is_drink correctly.
PROMPT;
    }
}
