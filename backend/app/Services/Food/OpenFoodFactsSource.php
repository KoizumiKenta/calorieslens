<?php

namespace App\Services\Food;

use App\Support\Atwater;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

/**
 * Open Food Facts — free, keyless, ~3M products worldwide (strong on packaged
 * goods, including Malaysian/SG brands). Returns rows already normalized to
 * our per-100g shape and Atwater-reconciled; the caller caches them.
 */
class OpenFoodFactsSource
{
    private const ENDPOINT = 'https://world.openfoodfacts.org/cgi/search.pl';

    /** @return array<int, array<string, mixed>> normalized food rows */
    public function search(string $query, int $limit = 20): array
    {
        try {
            $res = Http::timeout(6)
                ->withHeaders(['User-Agent' => 'CalorieLens/0.1 (dev)'])
                ->get(self::ENDPOINT, [
                    'search_terms' => $query,
                    'search_simple' => 1,
                    'action' => 'process',
                    'json' => 1,
                    'page_size' => $limit,
                    'fields' => 'code,product_name,brands,nutriments,serving_size,countries_tags',
                ]);
            if (! $res->ok()) {
                return [];
            }
            $products = $res->json('products') ?? [];
        } catch (\Throwable $e) {
            Log::warning('OFF search failed', ['q' => $query, 'e' => $e->getMessage()]);
            return [];
        }

        $rows = [];
        foreach ($products as $p) {
            $row = $this->normalize($p);
            if ($row !== null) {
                $rows[] = $row;
            }
        }
        return $rows;
    }

    private function normalize(array $p): ?array
    {
        $name = trim((string) ($p['product_name'] ?? ''));
        $code = (string) ($p['code'] ?? '');
        if ($name === '' || $code === '') {
            return null;
        }
        $n = $p['nutriments'] ?? [];

        $kcal = (float) ($n['energy-kcal_100g']
            ?? (isset($n['energy_100g']) ? $n['energy_100g'] / 4.184 : 0));
        $protein = (float) ($n['proteins_100g'] ?? 0);
        $carbs = (float) ($n['carbohydrates_100g'] ?? 0);
        $fat = (float) ($n['fat_100g'] ?? 0);
        $fiber = (float) ($n['fiber_100g'] ?? 0);
        $sugar = (float) ($n['sugars_100g'] ?? 0);
        // OFF stores sodium/salt in grams per 100g.
        $sodiumMg = isset($n['sodium_100g'])
            ? ((float) $n['sodium_100g']) * 1000
            : (isset($n['salt_100g']) ? ((float) $n['salt_100g']) / 2.5 * 1000 : 0);

        $kcal = Atwater::reconcile($kcal, $protein, $carbs, $fat);
        if (! Atwater::isPlausible($kcal, $protein, $carbs, $fat)) {
            return null;
        }

        return [
            'source' => 'off',
            'external_id' => $code,
            'name' => mb_substr($name, 0, 120),
            'brand' => ($b = trim((string) ($p['brands'] ?? ''))) !== '' ? mb_substr($b, 0, 80) : null,
            'region' => null,
            'emoji' => '🍴',
            'kcal' => round($kcal, 1),
            'protein_g' => round($protein, 2),
            'carbs_g' => round($carbs, 2),
            'fat_g' => round($fat, 2),
            'fiber_g' => round($fiber, 2),
            'sugar_g' => round($sugar, 2),
            'sodium_mg' => round($sodiumMg, 1),
            'portions' => $this->portions($p),
            'aliases' => [],
            'hydration_factor' => null,
            'verified' => false,
        ];
    }

    /** Parse "30 g" / "330ml" serving sizes into a logging portion. */
    private function portions(array $p): array
    {
        $serving = (string) ($p['serving_size'] ?? '');
        if (preg_match('/([\d.]+)\s*(g|ml)/i', $serving, $m)) {
            $grams = (float) $m[1];
            if ($grams > 0 && $grams < 2000) {
                return [['label' => '1 serving', 'grams' => $grams]];
            }
        }
        return [];
    }
}
