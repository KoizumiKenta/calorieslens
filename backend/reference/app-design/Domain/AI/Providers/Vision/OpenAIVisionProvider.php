<?php

declare(strict_types=1);

namespace App\Domain\AI\Providers\Vision;

use App\Domain\AI\Contracts\VisionProviderContract;
use App\Domain\AI\DTO\VisionAnalysis;
use App\Domain\AI\DTO\VisionRequest;
use App\Domain\AI\Exceptions\ProviderException;
use Illuminate\Support\Facades\Http;

final class OpenAIVisionProvider implements VisionProviderContract
{
    public function __construct(
        private readonly string $apiKey,
        private readonly string $model,
        private readonly int $timeoutSeconds,
    ) {}

    public function name(): string
    {
        return 'openai';
    }

    public function analyze(VisionRequest $request): VisionAnalysis
    {
        $startedAt = hrtime(true);

        $content = array_map(static fn (array $image) => [
            'type' => 'input_image',
            'image_url' => 'data:'.$image['mime'].';base64,'.base64_encode($image['bytes']),
            'detail' => 'high',
        ], $request->images);
        $content[] = ['type' => 'input_text', 'text' => 'Analyze this meal.'];

        $response = Http::withToken($this->apiKey)
            ->timeout($this->timeoutSeconds)
            ->post('https://api.openai.com/v1/responses', [
                'model' => $this->model,
                'instructions' => FoodVisionPrompt::system($request),
                'input' => [['role' => 'user', 'content' => $content]],
                'text' => [
                    'format' => [
                        'type' => 'json_schema',
                        'name' => 'food_analysis',
                        'schema' => FoodVisionPrompt::schema(),
                        'strict' => false,
                    ],
                ],
            ]);

        if ($response->status() === 429) {
            throw ProviderException::rateLimited($this->name());
        }
        if ($response->failed()) {
            throw new ProviderException($this->name(), "HTTP {$response->status()}", retryable: $response->status() >= 500, httpStatus: $response->status());
        }

        $json = json_decode($response->json('output.0.content.0.text', '') ?: 'null', true);
        if (! is_array($json)) {
            throw ProviderException::invalidResponse($this->name(), 'output is not valid JSON');
        }

        try {
            $usage = $response->json('usage', []);

            return VisionAnalysis::fromProviderJson(
                json: $json,
                provider: $this->name(),
                model: $this->model,
                latencyMs: (int) ((hrtime(true) - $startedAt) / 1_000_000),
                costUsd: round((($usage['input_tokens'] ?? 0) * 2.5 + ($usage['output_tokens'] ?? 0) * 10.0) / 1_000_000, 5),
            );
        } catch (\InvalidArgumentException $e) {
            throw ProviderException::invalidResponse($this->name(), $e->getMessage());
        }
    }
}
