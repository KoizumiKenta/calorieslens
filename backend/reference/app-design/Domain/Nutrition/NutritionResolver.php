<?php

declare(strict_types=1);

namespace App\Domain\Nutrition;

use App\Domain\Nutrition\Contracts\NutritionSourceContract;
use App\Domain\Nutrition\DTO\ResolvedFood;
use Illuminate\Contracts\Cache\Repository as Cache;
use Illuminate\Support\Facades\Log;

/**
 * Resolves food labels/barcodes to nutrition through the prioritized source
 * chain (docs/07-ai-services.md §5):
 *
 *   internal curated DB → Redis cache → USDA → OFF → Nutritionix → Edamam → Spoonacular
 *
 * Internal DB is always first (regional + verified data beats any external
 * source). External hits are cached 30 days and counted; popular ones are
 * promoted into food_items by the PromoteExternalFoodsJob.
 */
final class NutritionResolver
{
    private const CACHE_TTL_DAYS = 30;

    /** @param NutritionSourceContract[] $externalSources In priority order */
    public function __construct(
        private readonly InternalFoodSource $internal,
        private readonly array $externalSources,
        private readonly NutritionValidator $validator,
        private readonly Cache $cache,
    ) {}

    public function resolve(string $query, string $locale = 'en'): ?ResolvedFood
    {
        $normalized = $this->normalize($query);

        if ($hit = $this->internal->lookup($normalized, $locale)) {
            return $hit;
        }

        $cacheKey = 'nutr:q:'.md5("{$locale}:{$normalized}");
        if ($cached = $this->cache->get($cacheKey)) {
            return unserialize($cached, ['allowed_classes' => true]);
        }

        foreach ($this->externalSources as $source) {
            try {
                $resolved = $source->lookup($normalized, $locale);
            } catch (\Throwable $e) {
                Log::warning('Nutrition source failed', ['source' => $source->name(), 'error' => $e->getMessage()]);

                continue;
            }

            if ($resolved === null) {
                continue;
            }

            if (! $this->validator->isPlausible($resolved)) {
                Log::notice('Rejected implausible nutrition row', ['source' => $source->name(), 'query' => $normalized]);

                continue;
            }

            $this->cache->put($cacheKey, serialize($resolved), now()->addDays(self::CACHE_TTL_DAYS));
            $this->cache->increment('nutr:hits:'.md5($normalized)); // promotion signal

            return $resolved;
        }

        return null;
    }

    public function resolveBarcode(string $barcode): ?ResolvedFood
    {
        $barcode = preg_replace('/\D/', '', $barcode);

        if ($hit = $this->internal->lookupBarcode($barcode)) {
            return $hit;
        }

        $cacheKey = "nutr:bc:{$barcode}";
        if ($cached = $this->cache->get($cacheKey)) {
            return unserialize($cached, ['allowed_classes' => true]);
        }

        foreach ($this->externalSources as $source) {
            try {
                $resolved = $source->lookupBarcode($barcode);
            } catch (\Throwable) {
                continue;
            }

            if ($resolved !== null && $this->validator->isPlausible($resolved)) {
                $this->cache->put($cacheKey, serialize($resolved), now()->addDays(7));

                return $resolved;
            }
        }

        return null; // caller offers the community-submission flow
    }

    private function normalize(string $query): string
    {
        return mb_strtolower(trim(preg_replace('/\s+/', ' ', $query)));
    }
}
