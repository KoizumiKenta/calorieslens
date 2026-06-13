<?php

namespace Database\Seeders;

use App\Models\Food;
use Illuminate\Database\Seeder;

/**
 * Imports the curated SEA food seed (database/seeders/curated_foods.json,
 * generated from the Flutter app's FoodDatabase via tool/dump_foods.dart).
 * These are the trusted, regional entries that always rank first in search.
 */
class FoodSeeder extends Seeder
{
    public function run(): void
    {
        $path = database_path('seeders/curated_foods.json');
        $rows = json_decode(file_get_contents($path), true);

        foreach ($rows as $r) {
            $n = $r['per_100g'];
            Food::updateOrCreate(
                ['source' => 'curated', 'external_id' => $r['external_id']],
                [
                    'name' => $r['name'],
                    'brand' => $r['brand'],
                    'region' => $r['region'],
                    'emoji' => $r['emoji'] ?? '🍽️',
                    'kcal' => $n['kcal'],
                    'protein_g' => $n['protein_g'],
                    'carbs_g' => $n['carbs_g'],
                    'fat_g' => $n['fat_g'],
                    'fiber_g' => $n['fiber_g'] ?? 0,
                    'sugar_g' => $n['sugar_g'] ?? 0,
                    'sodium_mg' => $n['sodium_mg'] ?? 0,
                    'portions' => $r['portions'] ?? [],
                    'aliases' => $r['aliases'] ?? [],
                    'hydration_factor' => $r['hydration_factor'],
                    'verified' => true,
                    // Regional dishes get a popularity nudge so they outrank
                    // generic OFF entries for the same term.
                    'popularity' => $r['region'] !== null ? 100 : 50,
                ],
            );
        }
    }
}
