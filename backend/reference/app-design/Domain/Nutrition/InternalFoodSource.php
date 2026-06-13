<?php

declare(strict_types=1);

namespace App\Domain\Nutrition;

use App\Domain\Nutrition\DTO\ResolvedFood;
use App\Domain\Shared\NutritionFacts;
use Illuminate\Support\Facades\DB;

/**
 * First link in the resolver chain: the curated internal database.
 * Match strategy: exact (incl. translations) → trigram fuzzy ≥ 0.45 similarity,
 * ranked by verification and regional popularity.
 */
final class InternalFoodSource
{
    public function lookup(string $normalizedQuery, string $locale): ?ResolvedFood
    {
        $row = DB::selectOne(
            <<<'SQL'
            SELECT f.id, f.canonical_name, f.allergens,
                   n.kcal, n.protein_g, n.carbs_g, n.fat_g, n.fiber_g, n.sugar_g, n.sodium_mg,
                   GREATEST(
                       similarity(lower(f.canonical_name), :q),
                       COALESCE((SELECT max(similarity(lower(t.name), :q))
                                 FROM food_translations t WHERE t.food_item_id = f.id), 0)
                   ) AS score
            FROM food_items f
            JOIN food_nutrients_core n ON n.food_item_id = f.id
            WHERE f.deleted_at IS NULL
              AND f.visibility = 'global'
              AND (lower(f.canonical_name) % :q
                   OR EXISTS (SELECT 1 FROM food_translations t
                              WHERE t.food_item_id = f.id AND lower(t.name) % :q))
            ORDER BY score DESC,
                     (f.verification = 'verified') DESC,
                     (f.locale_origin = :locale) DESC,
                     f.popularity DESC
            LIMIT 1
            SQL,
            ['q' => $normalizedQuery, 'locale' => strtoupper($locale)],
        );

        if ($row === null || (float) $row->score < 0.45) {
            return null;
        }

        return new ResolvedFood(
            name: $row->canonical_name,
            per100g: new NutritionFacts(
                kcal: (float) $row->kcal,
                proteinG: (float) $row->protein_g,
                carbsG: (float) $row->carbs_g,
                fatG: (float) $row->fat_g,
                fiberG: $row->fiber_g !== null ? (float) $row->fiber_g : null,
                sugarG: $row->sugar_g !== null ? (float) $row->sugar_g : null,
                sodiumMg: $row->sodium_mg !== null ? (float) $row->sodium_mg : null,
            ),
            source: 'internal',
            sourceRef: $row->id,
            foodItemId: $row->id,
            allergens: json_decode($row->allergens ?? '[]', true) ?: [],
            matchScore: (float) $row->score,
        );
    }

    public function lookupBarcode(string $barcode): ?ResolvedFood
    {
        $row = DB::selectOne(
            <<<'SQL'
            SELECT b.product_name, b.brand, b.serving_grams, b.ingredients, b.food_item_id,
                   n.kcal, n.protein_g, n.carbs_g, n.fat_g, n.fiber_g, n.sugar_g, n.sodium_mg
            FROM barcode_products b
            JOIN food_nutrients_core n ON n.food_item_id = b.food_item_id
            WHERE b.barcode = :barcode
            SQL,
            ['barcode' => $barcode],
        );

        if ($row === null) {
            return null;
        }

        return new ResolvedFood(
            name: $row->product_name,
            per100g: new NutritionFacts(
                kcal: (float) $row->kcal,
                proteinG: (float) $row->protein_g,
                carbsG: (float) $row->carbs_g,
                fatG: (float) $row->fat_g,
                fiberG: $row->fiber_g !== null ? (float) $row->fiber_g : null,
                sugarG: $row->sugar_g !== null ? (float) $row->sugar_g : null,
                sodiumMg: $row->sodium_mg !== null ? (float) $row->sodium_mg : null,
            ),
            source: 'internal',
            sourceRef: $barcode,
            foodItemId: $row->food_item_id,
            brand: $row->brand,
            servingGrams: $row->serving_grams !== null ? (float) $row->serving_grams : null,
            ingredients: $row->ingredients,
        );
    }
}
