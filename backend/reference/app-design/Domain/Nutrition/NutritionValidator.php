<?php

declare(strict_types=1);

namespace App\Domain\Nutrition;

use App\Domain\Nutrition\DTO\ResolvedFood;

/**
 * Rejects corrupt external data before it reaches users or the cache.
 * External nutrition databases contain unit errors (kJ as kcal, per-serving
 * as per-100g) — this is the firewall.
 */
final class NutritionValidator
{
    public function isPlausible(ResolvedFood $food): bool
    {
        $n = $food->per100g;

        // Physical bounds per 100 g
        if ($n->kcal < 0 || $n->kcal > 900) {        // pure fat = 884 kcal/100g
            return false;
        }
        if ($n->proteinG > 100 || $n->carbsG > 100 || $n->fatG > 100) {
            return false;
        }
        if ($n->proteinG + $n->carbsG + $n->fatG > 105) { // small tolerance for rounding
            return false;
        }
        if (($n->sodiumMg ?? 0) > 40_000) {           // saltier than pure salt
            return false;
        }
        if (($n->sugarG ?? 0) > max($n->carbsG, 0) + 2) {
            return false;
        }

        // Atwater consistency (catches kJ-as-kcal errors: off by ~4.2×)
        return $n->isCalorieConsistent(tolerance: 0.20);
    }
}
