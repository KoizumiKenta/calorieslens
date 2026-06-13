<?php

declare(strict_types=1);

namespace App\Domain\AI\Resilience;

use Illuminate\Support\Facades\Context;
use Illuminate\Support\Facades\DB;

/**
 * Meters every provider call into ai_usage_events (cost dashboards,
 * quota anomaly detection) and Prometheus counters.
 */
final class UsageRecorder
{
    public function record(
        string $capability,
        string $provider,
        bool $success,
        int $latencyMs,
        ?string $model = null,
        ?int $tokensIn = null,
        ?int $tokensOut = null,
        ?float $costUsd = null,
    ): void {
        DB::table('ai_usage_events')->insert([
            'id' => (string) \Illuminate\Support\Str::uuid7(),
            'user_id' => Context::get('user_id'),
            'capability' => $capability,
            'provider' => $provider,
            'model' => $model ?? 'unknown',
            'tokens_in' => $tokensIn,
            'tokens_out' => $tokensOut,
            'cost_usd' => $costUsd,
            'latency_ms' => $latencyMs,
            'success' => $success,
            'created_at' => now(),
        ]);
    }
}
