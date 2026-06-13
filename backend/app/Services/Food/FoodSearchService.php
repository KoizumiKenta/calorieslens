<?php

namespace App\Services\Food;

use App\Models\Food;
use Illuminate\Support\Collection;

/**
 * The nutrition resolver (docs §NutritionResolver), trimmed to two sources:
 * the curated internal seed (SEA dishes — the regional moat, always ranked
 * first) and Open Food Facts. Local hits return instantly; OFF results are
 * upserted into the `foods` cache so the database grows with use and repeat
 * searches need no network. USDA / Nutritionix / an AI-estimate fallback slot
 * in here as additional sources without changing the contract.
 */
class FoodSearchService
{
    public function __construct(private readonly OpenFoodFactsSource $off) {}

    /** @return Collection<int, Food> ranked results */
    public function search(string $query, int $limit = 25): Collection
    {
        $query = trim($query);
        if (mb_strlen($query) < 2) {
            return collect();
        }

        $local = $this->localMatches($query, $limit);

        // Only reach out to OFF when the local cache is thin for this query —
        // keeps common searches instant and offline-friendly. OFF matches are
        // merged directly (not re-filtered through our LIKE), so products whose
        // names differ from the query phrase still surface.
        if ($local->count() < 8) {
            $remote = $this->cacheRemote($this->off->search($query, $limit));
            $local = $local
                ->concat($remote)
                ->unique('id')
                // Curated/verified first, then most-logged.
                ->sortByDesc(fn (Food $f) => ($f->verified ? 1_000_000 : 0) + $f->popularity)
                ->take($limit)
                ->values();
        }

        return $local;
    }

    private function localMatches(string $query, int $limit): Collection
    {
        $like = '%'.str_replace(['%', '_'], ['\%', '\_'], $query).'%';

        return Food::query()
            ->where(function ($q) use ($like) {
                $q->where('name', 'like', $like)
                    ->orWhere('aliases', 'like', $like);
            })
            // Curated/verified first, then most-logged, then alphabetical.
            ->orderByDesc('verified')
            ->orderByDesc('popularity')
            ->orderBy('name')
            ->limit($limit)
            ->get();
    }

    /**
     * Upsert normalized rows into the cache (keyed by source+external_id) and
     * return the resulting models in OFF's relevance order.
     *
     * @return Collection<int, Food>
     */
    private function cacheRemote(array $rows): Collection
    {
        return collect($rows)->map(fn (array $row) => Food::updateOrCreate(
            ['source' => $row['source'], 'external_id' => $row['external_id']],
            $row,
        ));
    }
}
