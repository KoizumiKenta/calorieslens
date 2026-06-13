<?php

declare(strict_types=1);

namespace App\Domain\AI\Providers\Vision;

use App\Domain\AI\Contracts\VisionProviderContract;
use App\Domain\AI\DTO\VisionAnalysis;
use App\Domain\AI\DTO\VisionRequest;
use App\Domain\AI\Exceptions\ProviderException;
use Illuminate\Support\Facades\Http;

final class GeminiVisionProvider implements VisionProviderContract
{
    public function __construct(
        private readonly string $apiKey,
        private readonly string $model,
        private readonly int $timeoutSeconds,
    ) {}

    public function name(): string
    {
        return 'gemini';
    }

    public function analyze(VisionRequest $request): VisionAnalysis
    {
        $startedAt = hrtime(true);

        $parts = array_map(static fn (array $image) => [
            'inline_data' => ['mime_type' => $image['mime'], 'data' => base64_encode($image['bytes'])],
        ], $request->images);
        $parts[] = ['text' => 'Analyze this meal.'];

        $response = Http::timeout($this->timeoutSeconds)
            ->post(
                "https://generativelanguage.googleapis.com/v1beta/models/{$this->model}:generateContent?key={$this->apiKey}",
                [
                    'system_instruction' => ['parts' => [['text' => FoodVisionPrompt::system($request)]]],
                    'contents' => [['role' => 'user', 'parts' => $parts]],
                    'generationConfig' => [
                        'response_mime_type' => 'application/json',
                        'response_schema' => self::toGeminiSchema(FoodVisionPrompt::schema()),
                        'temperature' => 0.2,
                    ],
                ],
            );

        if ($response->status() === 429) {
            throw ProviderException::rateLimited($this->name());
        }
        if ($response->failed()) {
            throw new ProviderException($this->name(), "HTTP {$response->status()}", retryable: $response->status() >= 500, httpStatus: $response->status());
        }

        $json = json_decode($response->json('candidates.0.content.parts.0.text', '') ?: 'null', true);
        if (! is_array($json)) {
            throw ProviderException::invalidResponse($this->name(), 'candidate is not valid JSON');
        }

        try {
            $usage = $response->json('usageMetadata', []);

            return VisionAnalysis::fromProviderJson(
                json: $json,
                provider: $this->name(),
                model: $this->model,
                latencyMs: (int) ((hrtime(true) - $startedAt) / 1_000_000),
                costUsd: round((($usage['promptTokenCount'] ?? 0) * 1.25 + ($usage['candidatesTokenCount'] ?? 0) * 5.0) / 1_000_000, 5),
            );
        } catch (\InvalidArgumentException $e) {
            throw ProviderException::invalidResponse($this->name(), $e->getMessage());
        }
    }

    /**
     * Gemini's OpenAPI-subset schema doesn't support $defs/$ref recursion —
     * flatten one level (components nest at most once: composite → leaves).
     */
    private static function toGeminiSchema(array $schema): array
    {
        $item = $schema['$defs']['item'];
        $leaf = $item;
        unset($leaf['properties']['components']);
        $item['properties']['components'] = ['type' => 'array', 'items' => $leaf];

        $schema['properties']['items']['items'] = $item;
        unset($schema['$defs']);

        return $schema;
    }
}
