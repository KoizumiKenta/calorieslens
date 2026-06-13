<?php

declare(strict_types=1);

namespace App\Domain\Nutrition\Contracts;

use App\Domain\Nutrition\DTO\ResolvedFood;

interface NutritionSourceContract
{
    public function name(): string;

    /**
     * Resolve a free-text food query to normalized per-100g nutrition.
     * Return null on no-match (next source tries); throw only on transport errors.
     */
    public function lookup(string $query, string $locale): ?ResolvedFood;

    /** Barcode lookup; null when the source doesn't support barcodes or has no match. */
    public function lookupBarcode(string $barcode): ?ResolvedFood;
}
