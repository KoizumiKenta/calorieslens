<?php

declare(strict_types=1);

namespace App\Domain\AI\DTO;

final readonly class OcrResult
{
    /**
     * @param  array<array{text: string, bbox: array, confidence: float}>  $words
     */
    public function __construct(
        public string $fullText,
        public array $words,
        public string $provider,
        public int $latencyMs,
    ) {}
}
