<?php

declare(strict_types=1);

namespace App\Domain\AI;

use App\Domain\AI\Contracts\VisionProviderContract;
use App\Domain\AI\DTO\VisionAnalysis;
use App\Domain\AI\DTO\VisionRequest;
use App\Domain\AI\Resilience\FallbackChain;
use Illuminate\Contracts\Container\Container;

/**
 * Single entry point for all AI capabilities. Business logic calls
 * AIManager and never touches a provider adapter directly.
 *
 *   $analysis = $ai->vision($request);
 *   $text     = $ai->transcribe($audio, 'audio/ogg', ['en', 'ms']);
 */
final class AIManager
{
    /** @var array<string, array<string, object>> capability => resolved adapters */
    private array $resolved = [];

    public function __construct(
        private readonly Container $container,
        private readonly FallbackChain $chain,
        private readonly array $config, // config('ai')
    ) {}

    public function vision(VisionRequest $request): VisionAnalysis
    {
        $model = $this->routeVisionModel($request->difficulty);

        return $this->chain->execute(
            capability: 'vision',
            providers: $this->providersFor('vision'),
            call: fn (VisionProviderContract $p) => $p->analyze($request),
            retries: $this->config['capabilities']['vision']['retries'],
        );
    }

    public function ocr(string $imageBytes, string $mime, array $languageHints = []): DTO\OcrResult
    {
        return $this->chain->execute(
            'ocr',
            $this->providersFor('ocr'),
            fn (Contracts\OcrProviderContract $p) => $p->extract($imageBytes, $mime, $languageHints),
            $this->config['capabilities']['ocr']['retries'],
        );
    }

    public function transcribe(string $audioBytes, string $mime, array $languageHints = []): string
    {
        return $this->chain->execute(
            'stt',
            $this->providersFor('stt'),
            fn (Contracts\SpeechProviderContract $p) => $p->transcribe($audioBytes, $mime, $languageHints),
            $this->config['capabilities']['stt']['retries'],
        );
    }

    public function complete(string $system, array $messages, ?array $schema = null): array
    {
        return $this->chain->execute(
            'chat',
            $this->providersFor('chat'),
            fn (Contracts\LlmProviderContract $p) => $p->complete($system, $messages, $schema),
            $this->config['capabilities']['chat']['retries'],
        );
    }

    /** @param callable(string): void $onDelta */
    public function streamChat(string $system, array $messages, array $tools, callable $onDelta): array
    {
        return $this->chain->execute(
            'chat',
            $this->providersFor('chat'),
            fn (Contracts\LlmProviderContract $p) => $p->stream($system, $messages, $tools, $onDelta),
            retries: 0, // streams are not transparently retryable mid-flight
        );
    }

    /** Cheap-tier routing for easy scans (docs/07 §9). */
    private function routeVisionModel(float $difficulty): ?string
    {
        if ($difficulty <= $this->config['routing']['cheap_tier_max_difficulty']) {
            $first = $this->config['capabilities']['vision']['chain'][0];

            return $this->config['routing']['cheap_models'][$first] ?? null;
        }

        return null;
    }

    /** @return array<string, object> */
    private function providersFor(string $capability): array
    {
        return $this->resolved[$capability] ??= collect($this->config['capabilities'][$capability]['chain'])
            ->mapWithKeys(fn (string $name) => [
                $name => $this->container->make("ai.{$capability}.{$name}"),
            ])
            ->all();
    }
}
