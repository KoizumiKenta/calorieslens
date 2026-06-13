<?php

declare(strict_types=1);

namespace App\Domain\AI\Resilience;

use App\Domain\AI\Events\ProviderDegraded;
use Illuminate\Contracts\Cache\Repository as Cache;
use Illuminate\Contracts\Events\Dispatcher;

/**
 * Per-(capability, provider) circuit breaker backed by Redis so state is
 * shared across all workers. Closed → Open after N failures in the window;
 * Open → Half-open after cooldown; one probe success closes it.
 */
final class CircuitBreaker
{
    public function __construct(
        private readonly Cache $cache,
        private readonly Dispatcher $events,
        private readonly int $failureThreshold,
        private readonly int $windowSeconds,
        private readonly int $cooldownSeconds,
    ) {}

    public function isAvailable(string $capability, string $provider): bool
    {
        $openedAt = $this->cache->get($this->key($capability, $provider, 'opened_at'));

        if ($openedAt === null) {
            return true;
        }

        // Half-open: allow a single probe after cooldown
        if (time() - (int) $openedAt >= $this->cooldownSeconds) {
            return $this->cache->add($this->key($capability, $provider, 'probe'), 1, $this->cooldownSeconds);
        }

        return false;
    }

    public function recordSuccess(string $capability, string $provider): void
    {
        $this->cache->forget($this->key($capability, $provider, 'opened_at'));
        $this->cache->forget($this->key($capability, $provider, 'failures'));
        $this->cache->forget($this->key($capability, $provider, 'probe'));
    }

    public function recordFailure(string $capability, string $provider): void
    {
        $failuresKey = $this->key($capability, $provider, 'failures');

        $failures = $this->cache->increment($failuresKey);
        if ($failures === 1) {
            // First failure starts the rolling window
            $this->cache->put($failuresKey, 1, $this->windowSeconds);
        }

        if ($failures >= $this->failureThreshold) {
            $wasOpen = $this->cache->get($this->key($capability, $provider, 'opened_at')) !== null;
            $this->cache->put($this->key($capability, $provider, 'opened_at'), time(), $this->cooldownSeconds * 10);

            if (! $wasOpen) {
                $this->events->dispatch(new ProviderDegraded($capability, $provider));
            }
        }
    }

    private function key(string $capability, string $provider, string $suffix): string
    {
        return "ai:cb:{$capability}:{$provider}:{$suffix}";
    }
}
