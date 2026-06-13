<?php

declare(strict_types=1);

namespace App\Domain\AI\Resilience;

use App\Domain\AI\Exceptions\AllProvidersFailedException;
use App\Domain\AI\Exceptions\ProviderException;
use Closure;
use Illuminate\Support\Facades\Log;

/**
 * Tries providers in configured order, skipping open circuits, retrying
 * retryable failures with jittered backoff, then failing over.
 */
final class FallbackChain
{
    public function __construct(
        private readonly CircuitBreaker $breaker,
        private readonly UsageRecorder $usage,
    ) {}

    /**
     * @template T
     *
     * @param  array<string, object>  $providers  name => adapter, in priority order
     * @param  Closure(object): T  $call  Invokes the adapter
     * @return T
     */
    public function execute(string $capability, array $providers, Closure $call, int $retries = 2)
    {
        $errors = [];

        foreach ($providers as $name => $provider) {
            if (! $this->breaker->isAvailable($capability, $name)) {
                $errors[$name] = 'circuit open';

                continue;
            }

            for ($attempt = 0; $attempt <= $retries; $attempt++) {
                $startedAt = hrtime(true);

                try {
                    $result = $call($provider);

                    $this->breaker->recordSuccess($capability, $name);
                    $this->usage->record($capability, $name, success: true, latencyMs: $this->elapsedMs($startedAt));

                    return $result;
                } catch (ProviderException $e) {
                    $this->breaker->recordFailure($capability, $name);
                    $this->usage->record($capability, $name, success: false, latencyMs: $this->elapsedMs($startedAt));
                    $errors[$name] = $e->getMessage();

                    Log::warning('AI provider call failed', [
                        'capability' => $capability, 'provider' => $name,
                        'attempt' => $attempt, 'retryable' => $e->retryable, 'error' => $e->getMessage(),
                    ]);

                    if (! $e->retryable || $attempt === $retries) {
                        break; // fail over to next provider
                    }

                    usleep((int) (min(2 ** $attempt, 8) * 1_000_000 * (0.5 + mt_rand() / mt_getrandmax())));
                }
            }
        }

        throw new AllProvidersFailedException($capability, $errors);
    }

    private function elapsedMs(int|float $startedAtNs): int
    {
        return (int) ((hrtime(true) - $startedAtNs) / 1_000_000);
    }
}
