<?php

declare(strict_types=1);

namespace App\Domain\AI\DTO;

final readonly class VisionRequest
{
    /**
     * @param  array<array{bytes: string, mime: string, angle: ?string}>  $images
     * @param  array<string>  $localeDishVocabulary  Regional dish names injected
     *                        into the prompt for the user's locale (docs/07 §2)
     * @param  string|null  $depthMapPng  Raw depth map when device supports it
     * @param  array|null  $beforeItems  For after-photo scans: the before-scan
     *                     item list the model must score remaining fractions on
     * @param  float  $difficulty  0–1, drives cheap-vs-frontier model routing
     */
    public function __construct(
        public array $images,
        public string $locale,
        public array $localeDishVocabulary = [],
        public ?string $depthMapPng = null,
        public ?array $beforeItems = null,
        public float $difficulty = 0.5,
    ) {}

    public function isBeforeAfter(): bool
    {
        return $this->beforeItems !== null;
    }
}
