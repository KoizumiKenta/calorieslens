<?php

declare(strict_types=1);

namespace App\Domain\Recognition\DTO;

final readonly class PreparedScan
{
    /** @param array<array{bytes: string, mime: string, angle: ?string}> $images */
    public function __construct(
        public array $images,
        public ?string $dedupedResultId,
        public float $difficulty,
    ) {}
}
