<?php

declare(strict_types=1);

namespace App\Domain\Recognition;

use App\Domain\AI\DTO\DetectedItem;

/**
 * Fuses independent portion signals into grams + an honest range
 * (docs/07-ai-services.md §2). Inverse-variance weighted mean; range is
 * the 80% interval (±1.28σ) — surfaced to users as grams_range.
 */
final class PortionEstimator
{
    private const BASIS_RELATIVE_SIGMA = [
        'plate_fraction' => 0.30,
        'count' => 0.18,
        'reference_object' => 0.18,
        'depth' => 0.12,
    ];

    /**
     * @param  float|null  $scaleHintPxPerMm  From detected reference objects
     * @param  float|null  $depthVolumeMl  From device depth map, when present
     * @param  float|null  $densityGPerMl  From food_items.density_g_ml
     * @param  array{avg_ratio: float, n: int}|null  $userPrior  Learned portion bias
     * @return array{grams: float, low: float, high: float, confidence: float}
     */
    public function estimate(
        DetectedItem $item,
        ?float $scaleHintPxPerMm,
        ?float $depthVolumeMl,
        ?float $densityGPerMl,
        ?array $userPrior,
    ): array {
        $estimates = [];

        // Signal 1: the vision model's own estimate, weighted by its declared basis
        $sigma = self::BASIS_RELATIVE_SIGMA[$item->portion['basis']] ?? 0.30;
        // A confirmed reference object in frame tightens the vision estimate
        if ($scaleHintPxPerMm !== null && $item->portion['basis'] === 'plate_fraction') {
            $sigma *= 0.75;
        }
        $estimates[] = ['grams' => $item->portion['grams'], 'sigma' => $item->portion['grams'] * $sigma];

        // Signal 2: depth-derived volume × density (strongest signal when present)
        if ($depthVolumeMl !== null && $densityGPerMl !== null && $depthVolumeMl > 0) {
            $grams = $depthVolumeMl * $densityGPerMl;
            $estimates[] = ['grams' => $grams, 'sigma' => $grams * self::BASIS_RELATIVE_SIGMA['depth']];
        }

        // Inverse-variance weighted fusion
        $weightSum = 0.0;
        $weighted = 0.0;
        foreach ($estimates as $e) {
            $w = 1.0 / ($e['sigma'] ** 2);
            $weightSum += $w;
            $weighted += $w * $e['grams'];
        }
        $grams = $weighted / $weightSum;
        $fusedSigma = sqrt(1.0 / $weightSum);

        // Signal 3: per-user learned bias, applied multiplicatively once stable
        if ($userPrior !== null && $userPrior['n'] >= 3 && abs($userPrior['avg_ratio'] - 1.0) > 0.10) {
            $grams *= $userPrior['avg_ratio'];
        }

        $confidence = max(0.05, min(0.99, 1.0 - ($fusedSigma / $grams)));

        return [
            'grams' => round($grams, 1),
            'low' => round(max(1.0, $grams - 1.28 * $fusedSigma), 1),
            'high' => round($grams + 1.28 * $fusedSigma, 1),
            'confidence' => round($confidence, 3),
        ];
    }

    /**
     * Meal-level kcal range: root-sum-square of per-item half-ranges around
     * the total (items are treated as independent; documented assumption).
     *
     * @param  array<array{kcal: float, kcal_low: float, kcal_high: float}>  $items
     * @return array{low: float, high: float}
     */
    public function mealKcalRange(array $items): array
    {
        $total = array_sum(array_column($items, 'kcal'));
        $variance = 0.0;
        foreach ($items as $item) {
            $halfRange = ($item['kcal_high'] - $item['kcal_low']) / 2.0;
            $variance += $halfRange ** 2;
        }
        $spread = sqrt($variance);

        return ['low' => round(max(0, $total - $spread)), 'high' => round($total + $spread)];
    }
}
