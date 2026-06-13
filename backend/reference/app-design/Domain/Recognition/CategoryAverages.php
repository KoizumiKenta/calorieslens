<?php

declare(strict_types=1);

namespace App\Domain\Recognition;

use App\Domain\Shared\NutritionFacts;

/**
 * Last-resort per-100g category averages when no nutrition source matches a
 * detected label. Items using these are flagged low-confidence in the UI so
 * the user verifies — better an honest rough number than a blocked flow.
 */
final class CategoryAverages
{
    private const TABLE = [
        'protein' => [165.0, 25.0, 0.0, 7.0],
        'grain' => [150.0, 3.5, 30.0, 1.5],
        'vegetable' => [35.0, 2.0, 6.0, 0.3],
        'fruit' => [60.0, 0.8, 14.0, 0.3],
        'dairy' => [90.0, 5.5, 6.0, 5.0],
        'beverage' => [40.0, 0.5, 9.0, 0.2],
        'dessert' => [320.0, 4.0, 45.0, 14.0],
        'mixed_dish' => [180.0, 8.0, 20.0, 8.0],
    ];

    public static function for(string $categoryHint): NutritionFacts
    {
        [$kcal, $protein, $carbs, $fat] = self::TABLE[$categoryHint] ?? self::TABLE['mixed_dish'];

        return new NutritionFacts(kcal: $kcal, proteinG: $protein, carbsG: $carbs, fatG: $fat);
    }
}
