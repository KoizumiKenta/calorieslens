<?php

declare(strict_types=1);

namespace App\Domain\AI\DTO;

use InvalidArgumentException;

final readonly class VisionAnalysis
{
    /**
     * @param  DetectedItem[]  $items
     * @param  array  $referenceObjects  [{type, bbox, est_px_per_mm}]
     * @param  array  $imageQuality  {blur, lighting, occlusion}
     */
    public function __construct(
        public array $items,
        public array $referenceObjects,
        public array $imageQuality,
        public string $mealReasoning,
        public string $provider,
        public string $model,
        public int $latencyMs,
        public float $costUsd,
    ) {}

    /**
     * Parse + validate the canonical JSON schema every provider must emit.
     * One repair attempt happens provider-side; here we are strict.
     */
    public static function fromProviderJson(
        array $json,
        string $provider,
        string $model,
        int $latencyMs,
        float $costUsd,
    ): self {
        if (! isset($json['items']) || ! is_array($json['items'])) {
            throw new InvalidArgumentException("Vision response from {$provider} missing items[]");
        }

        return new self(
            items: array_map(DetectedItem::fromArray(...), $json['items']),
            referenceObjects: $json['reference_objects'] ?? [],
            imageQuality: $json['image_quality'] ?? [],
            mealReasoning: $json['meal_reasoning'] ?? '',
            provider: $provider,
            model: $model,
            latencyMs: $latencyMs,
            costUsd: $costUsd,
        );
    }

    /** Best px-per-mm scale hint from detected reference objects, if any. */
    public function scaleHint(): ?float
    {
        $scales = array_column($this->referenceObjects, 'est_px_per_mm');

        return $scales === [] ? null : array_sum($scales) / count($scales);
    }
}
