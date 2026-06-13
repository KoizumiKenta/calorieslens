<?php

declare(strict_types=1);

namespace App\Domain\Personalization;

use Illuminate\Support\Facades\DB;

/**
 * Read/write access to per-user learned priors (docs/07 §7).
 * Written by PersonalizationLearner on EntryCorrected events; read by the
 * recognition pipeline. Strictly per-user — priors are never pooled.
 */
final class PriorStore
{
    private const EW_ALPHA = 0.3; // exponential weighting for portion bias updates

    /** @return array{avg_ratio: float, n: int}|null */
    public function portionBias(string $userId, string $foodItemId): ?array
    {
        $row = DB::table('user_food_priors')
            ->where(['user_id' => $userId, 'kind' => 'portion_bias', 'match_key' => $foodItemId])
            ->value('payload');

        return $row === null ? null : json_decode($row, true);
    }

    public function recordPortionCorrection(string $userId, string $foodItemId, float $predictedGrams, float $correctedGrams): void
    {
        if ($predictedGrams <= 0) {
            return;
        }

        $ratio = max(0.2, min(5.0, $correctedGrams / $predictedGrams));
        $existing = $this->portionBias($userId, $foodItemId);

        $payload = $existing === null
            ? ['avg_ratio' => $ratio, 'n' => 1]
            : [
                'avg_ratio' => round((1 - self::EW_ALPHA) * $existing['avg_ratio'] + self::EW_ALPHA * $ratio, 4),
                'n' => $existing['n'] + 1,
            ];

        DB::table('user_food_priors')->upsert(
            [[
                'id' => (string) \Illuminate\Support\Str::uuid7(),
                'user_id' => $userId,
                'kind' => 'portion_bias',
                'match_key' => $foodItemId,
                'payload' => json_encode($payload),
                'strength' => min(1.0, $payload['n'] / 10),
                'updated_at' => now(),
            ]],
            ['user_id', 'kind', 'match_key'],
            ['payload', 'strength', 'updated_at'],
        );
    }

    /** Label remap: "model said X, this user means Y" after ≥2 identical corrections. */
    public function labelRemap(string $userId, string $detectedLabel): ?string
    {
        $payload = DB::table('user_food_priors')
            ->where(['user_id' => $userId, 'kind' => 'label_remap', 'match_key' => mb_strtolower($detectedLabel)])
            ->where('strength', '>=', 0.2)
            ->value('payload');

        return $payload === null ? null : (json_decode($payload, true)['remap_to'] ?? null);
    }
}
