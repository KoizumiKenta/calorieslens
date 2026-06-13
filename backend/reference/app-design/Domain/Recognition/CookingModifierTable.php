<?php

declare(strict_types=1);

namespace App\Domain\Recognition;

use App\Domain\Shared\NutritionFacts;
use Illuminate\Support\Facades\DB;

/**
 * Applies cooking-method adjustments (grilled vs deep-fried changes the
 * numbers materially). Backed by the cooking_modifiers table so
 * nutritionists tune values in admin without deploys.
 */
final class CookingModifierTable
{
    public function apply(NutritionFacts $facts, ?string $method, float $grams): NutritionFacts
    {
        if ($method === null) {
            return $facts;
        }

        $mod = $this->table()[$method] ?? null;
        if ($mod === null) {
            return $facts;
        }

        $addedFat = $mod->fat_add_g_per_100g * $grams / 100.0;

        return new NutritionFacts(
            kcal: round($facts->kcal * (float) $mod->kcal_mult + $addedFat * 9.0, 1),
            proteinG: $facts->proteinG,
            carbsG: $facts->carbsG,
            fatG: round($facts->fatG + $addedFat, 2),
            fiberG: $facts->fiberG,
            sugarG: $facts->sugarG,
            sodiumMg: $facts->sodiumMg === null
                ? null
                : round($facts->sodiumMg + $mod->sodium_add_mg_per_100g * $grams / 100.0, 1),
        );
    }

    private function table(): array
    {
        return cache()->remember(
            'cooking-modifiers',
            3600,
            static fn () => DB::table('cooking_modifiers')->get()->keyBy('method')->all(),
        );
    }
}
