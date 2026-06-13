<?php

declare(strict_types=1);

namespace App\Domain\Nutrition\Sources;

use App\Domain\Nutrition\Contracts\NutritionSourceContract;
use App\Domain\Nutrition\DTO\ResolvedFood;
use App\Domain\Shared\NutritionFacts;
use Illuminate\Support\Facades\Http;

/**
 * USDA FoodData Central adapter. Best for generic/raw foods; no barcodes.
 * Other adapters (OpenFoodFactsSource, NutritionixSource, EdamamSource,
 * SpoonacularSource) follow this exact shape — implement the contract,
 * normalize to per-100g, map nutrient IDs, never throw on no-match.
 */
final class UsdaFoodDataSource implements NutritionSourceContract
{
    private const NUTRIENT_IDS = [
        'kcal' => 1008, 'protein' => 1003, 'fat' => 1004, 'carbs' => 1005,
        'fiber' => 1079, 'sugar' => 2000, 'sodium' => 1093,
    ];

    public function __construct(private readonly string $apiKey) {}

    public function name(): string
    {
        return 'usda';
    }

    public function lookup(string $query, string $locale): ?ResolvedFood
    {
        $response = Http::timeout(5)
            ->retry(1, 200)
            ->get('https://api.nal.usda.gov/fdc/v1/foods/search', [
                'api_key' => $this->apiKey,
                'query' => $query,
                'dataType' => 'Foundation,SR Legacy,Survey (FNDDS)',
                'pageSize' => 1,
            ]);

        $food = $response->json('foods.0');
        if ($food === null) {
            return null;
        }

        $byId = collect($food['foodNutrients'] ?? [])
            ->keyBy(fn (array $n) => $n['nutrientId'] ?? 0)
            ->map(fn (array $n) => (float) ($n['value'] ?? 0));

        $kcal = $byId->get(self::NUTRIENT_IDS['kcal']);
        if ($kcal === null) {
            return null;
        }

        return new ResolvedFood(
            name: ucwords(strtolower($food['description'])),
            per100g: new NutritionFacts(
                kcal: $kcal,
                proteinG: $byId->get(self::NUTRIENT_IDS['protein'], 0.0),
                carbsG: $byId->get(self::NUTRIENT_IDS['carbs'], 0.0),
                fatG: $byId->get(self::NUTRIENT_IDS['fat'], 0.0),
                fiberG: $byId->get(self::NUTRIENT_IDS['fiber']),
                sugarG: $byId->get(self::NUTRIENT_IDS['sugar']),
                sodiumMg: $byId->get(self::NUTRIENT_IDS['sodium']),
            ),
            source: 'usda',
            sourceRef: (string) $food['fdcId'],
            foodItemId: null,
            matchScore: 0.8,
        );
    }

    public function lookupBarcode(string $barcode): ?ResolvedFood
    {
        return null; // USDA has no barcode index — chain falls through to OFF
    }
}
