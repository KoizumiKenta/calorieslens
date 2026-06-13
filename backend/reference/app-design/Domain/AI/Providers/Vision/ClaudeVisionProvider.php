<?php

declare(strict_types=1);

namespace App\Domain\AI\Providers\Vision;

use App\Domain\AI\Contracts\VisionProviderContract;
use App\Domain\AI\DTO\VisionAnalysis;
use App\Domain\AI\DTO\VisionRequest;
use App\Domain\AI\Exceptions\ProviderException;
use Illuminate\Support\Facades\Http;
use JsonException;

final class ClaudeVisionProvider implements VisionProviderContract
{
    public function __construct(
        private readonly string $apiKey,
        private readonly string $model,
        private readonly int $timeoutSeconds,
    ) {}

    public function name(): string
    {
        return 'claude';
    }

    public function analyze(VisionRequest $request): VisionAnalysis
    {
        $startedAt = hrtime(true);

        $content = [];
        foreach ($request->images as $image) {
            $content[] = [
                'type' => 'image',
                'source' => [
                    'type' => 'base64',
                    'media_type' => $image['mime'],
                    'data' => base64_encode($image['bytes']),
                ],
            ];
        }
        $content[] = ['type' => 'text', 'text' => 'Analyze this meal.'];

        $response = Http::withHeaders([
            'x-api-key' => $this->apiKey,
            'anthropic-version' => '2023-06-01',
        ])
            ->timeout($this->timeoutSeconds)
            ->post('https://api.anthropic.com/v1/messages', [
                'model' => $this->model,
                'max_tokens' => 4096,
                'system' => FoodVisionPrompt::system($request),
                'messages' => [['role' => 'user', 'content' => $content]],
                // Structured output via forced tool call carrying our schema
                'tools' => [[
                    'name' => 'report_food_analysis',
                    'description' => 'Report the structured food analysis.',
                    'input_schema' => FoodVisionPrompt::schema(),
                ]],
                'tool_choice' => ['type' => 'tool', 'name' => 'report_food_analysis'],
            ]);

        if ($response->status() === 429) {
            throw ProviderException::rateLimited($this->name());
        }
        if ($response->failed()) {
            throw new ProviderException($this->name(), "HTTP {$response->status()}: ".$response->body(), retryable: $response->status() >= 500, httpStatus: $response->status());
        }

        $toolUse = collect($response->json('content', []))->firstWhere('type', 'tool_use');
        if ($toolUse === null) {
            throw ProviderException::invalidResponse($this->name(), 'no tool_use block in response');
        }

        try {
            return VisionAnalysis::fromProviderJson(
                json: $toolUse['input'],
                provider: $this->name(),
                model: $this->model,
                latencyMs: (int) ((hrtime(true) - $startedAt) / 1_000_000),
                costUsd: $this->estimateCost($response->json('usage', [])),
            );
        } catch (JsonException|\InvalidArgumentException $e) {
            throw ProviderException::invalidResponse($this->name(), $e->getMessage());
        }
    }

    private function estimateCost(array $usage): float
    {
        // Pricing table maintained in config/ai-pricing.php; simplified here
        $in = ($usage['input_tokens'] ?? 0) / 1_000_000;
        $out = ($usage['output_tokens'] ?? 0) / 1_000_000;

        return round($in * 3.0 + $out * 15.0, 5);
    }
}
