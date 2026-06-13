<?php

declare(strict_types=1);

namespace App\Domain\AI\DTO;

use InvalidArgumentException;

final readonly class DetectedItem
{
    /**
     * @param  array{grams: float, low: float, high: float, serving_label: ?string, basis: string}  $portion
     * @param  DetectedItem[]  $components  Filled for composite dishes
     * @param  array{0: float, 1: float, 2: float, 3: float}|null  $bbox  Normalized [x,y,w,h]
     */
    public function __construct(
        public string $label,
        public string $categoryHint,
        public bool $isComposite,
        public array $components,
        public ?string $cookingMethod,
        public array $portion,
        public ?array $bbox,
        public float $confidence,
        public string $reasoning,
        public ?float $remainingFraction = null, // before/after flow only
    ) {}

    public static function fromArray(array $a): self
    {
        foreach (['label', 'portion', 'confidence'] as $required) {
            if (! isset($a[$required])) {
                throw new InvalidArgumentException("Detected item missing '{$required}'");
            }
        }

        $confidence = (float) $a['confidence'];
        if ($confidence < 0.0 || $confidence > 1.0) {
            throw new InvalidArgumentException("Confidence out of range: {$confidence}");
        }

        return new self(
            label: (string) $a['label'],
            categoryHint: (string) ($a['category_hint'] ?? 'mixed_dish'),
            isComposite: (bool) ($a['is_composite'] ?? false),
            components: array_map(self::fromArray(...), $a['components'] ?? []),
            cookingMethod: $a['cooking_method'] ?? null,
            portion: [
                'grams' => (float) $a['portion']['grams'],
                'low' => (float) ($a['portion']['low'] ?? $a['portion']['grams'] * 0.8),
                'high' => (float) ($a['portion']['high'] ?? $a['portion']['grams'] * 1.25),
                'serving_label' => $a['portion']['serving_label'] ?? null,
                'basis' => $a['portion']['basis'] ?? 'plate_fraction',
            ],
            bbox: $a['bbox'] ?? null,
            confidence: $confidence,
            reasoning: (string) ($a['reasoning'] ?? ''),
            remainingFraction: isset($a['remaining_fraction']) ? (float) $a['remaining_fraction'] : null,
        );
    }
}
