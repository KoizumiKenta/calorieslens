<?php

declare(strict_types=1);

namespace App\Domain\AI\Providers\Vision;

use App\Domain\AI\DTO\VisionRequest;

/**
 * Canonical prompt + JSON schema shared by every vision provider so results
 * are comparable across the fallback chain and the eval harness benchmarks
 * apples to apples. Version-tagged: bump VERSION on any change (CI runs the
 * golden-set eval when this file changes).
 */
final class FoodVisionPrompt
{
    public const VERSION = '2026-06-01.1';

    public static function system(VisionRequest $request): string
    {
        $vocab = $request->localeDishVocabulary !== []
            ? "Regional dishes common for this user's locale ({$request->locale}): "
              .implode(', ', $request->localeDishVocabulary)
              .'. Prefer these names when the dish matches; decompose them into components.'
            : '';

        $beforeAfter = $request->isBeforeAfter()
            ? 'TASK MODE: BEFORE/AFTER. The first image is the meal before eating; the second is after. '
              .'For each item in the provided before-list, estimate remaining_fraction (0 = fully eaten, 1 = untouched). '
              .'Before-list: '.json_encode($request->beforeItems)
            : 'TASK MODE: DETECTION. Detect every distinct food and beverage item.';

        return <<<PROMPT
        You are a food recognition system for a nutrition tracker. Analyze the meal image(s) and emit ONLY JSON matching the provided schema.

        {$beforeAfter}

        Rules:
        - Segment and identify each food independently; one entry per distinct food.
        - Mixed/composite dishes (fried rice, curries, nasi lemak, noodle soups, salads, stews): set is_composite=true and decompose into components with per-component portions.
        - Estimate portion in grams with a low–high range. Declare the estimation basis: plate_fraction | reference_object | depth | count.
        - Use visible reference objects (cutlery ~19 cm fork / 20 cm knife / 16 cm spoon, credit card 85.6×54 mm, coins, standard dinner plate 26–28 cm, human hand) to calibrate size; report them in reference_objects with estimated px-per-mm.
        - Infer cooking method from visual cues (char marks, oil sheen, batter) — it changes calories.
        - NEVER guess foods that are occluded or ambiguous; lower confidence instead and say why in reasoning.
        - Confidence is your honest probability the label is correct. Reasoning must be one user-readable sentence citing visual evidence.
        - Multiple images of the same meal are different angles: reconcile them into ONE item list.
        {$vocab}
        PROMPT;
    }

    /** JSON Schema enforced via provider structured-output where supported. */
    public static function schema(): array
    {
        $portion = [
            'type' => 'object',
            'properties' => [
                'grams' => ['type' => 'number'],
                'low' => ['type' => 'number'],
                'high' => ['type' => 'number'],
                'serving_label' => ['type' => ['string', 'null']],
                'basis' => ['type' => 'string', 'enum' => ['plate_fraction', 'reference_object', 'depth', 'count']],
            ],
            'required' => ['grams', 'basis'],
        ];

        $item = [
            'type' => 'object',
            'properties' => [
                'label' => ['type' => 'string'],
                'category_hint' => ['type' => 'string'],
                'is_composite' => ['type' => 'boolean'],
                'components' => ['type' => 'array', 'items' => ['$ref' => '#/$defs/item']],
                'cooking_method' => ['type' => ['string', 'null'],
                    'enum' => ['raw', 'boiled', 'steamed', 'grilled', 'baked', 'stir_fried', 'deep_fried', null]],
                'portion' => $portion,
                'bbox' => ['type' => ['array', 'null'], 'items' => ['type' => 'number'], 'minItems' => 4, 'maxItems' => 4],
                'confidence' => ['type' => 'number', 'minimum' => 0, 'maximum' => 1],
                'reasoning' => ['type' => 'string'],
                'remaining_fraction' => ['type' => ['number', 'null'], 'minimum' => 0, 'maximum' => 1],
            ],
            'required' => ['label', 'portion', 'confidence', 'reasoning'],
        ];

        return [
            '$defs' => ['item' => $item],
            'type' => 'object',
            'properties' => [
                'items' => ['type' => 'array', 'items' => ['$ref' => '#/$defs/item']],
                'reference_objects' => ['type' => 'array'],
                'plate' => ['type' => 'object'],
                'image_quality' => ['type' => 'object'],
                'meal_reasoning' => ['type' => 'string'],
            ],
            'required' => ['items', 'meal_reasoning'],
        ];
    }
}
