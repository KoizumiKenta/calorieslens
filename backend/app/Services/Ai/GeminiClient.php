<?php

namespace App\Services\Ai;

use Illuminate\Support\Facades\Http;

/**
 * One place to call Gemini's generateContent with a model chain: try each
 * model in order, retry transient 429/503 once, fall through to the next
 * (cheaper, higher-quota) model on a real quota wall, and only report
 * quota_exceeded when every model is spent.
 */
class GeminiClient
{
    /**
     * @param  array<int,string>  $models
     * @return array<string,mixed> decoded JSON, or ['error' => ...]
     */
    public function generate(array $payload, array $models): array
    {
        $key = config('calorielens.gemini_key');
        if (! $key) {
            return ['error' => 'no_api_key', 'message' => 'GEMINI_API_KEY is not set on the server.'];
        }

        $last = ['error' => 'provider_error', 'message' => 'No model attempted.'];
        foreach (array_values($models) as $i => $model) {
            $url = "https://generativelanguage.googleapis.com/v1beta/models/{$model}:generateContent";

            $r = $this->post($url, $key, $payload);
            if (in_array($r['status'], [429, 503], true)) {
                sleep(2);
                $r = $this->post($url, $key, $payload);
            }

            if ($r['status'] === null) {
                $last = ['error' => 'provider_unreachable', 'message' => $r['error']];
                continue;
            }
            if ($r['status'] === 200) {
                $text = data_get($r['body'], 'candidates.0.content.parts.0.text');
                $data = is_string($text) ? json_decode($text, true) : null;
                if (is_array($data)) {
                    return $data;
                }
                $last = ['error' => 'no_structured_output', 'message' => 'Gemini returned no parseable JSON.'];
                continue;
            }

            $msg = data_get($r['body'], 'error.message', "HTTP {$r['status']} from Gemini");
            $isQuota = $r['status'] === 429 || stripos($msg, 'quota') !== false
                || stripos($msg, 'RESOURCE_EXHAUSTED') !== false;
            if ($isQuota && $i < count($models) - 1) {
                continue;
            }
            if ($isQuota) {
                return ['error' => 'quota_exceeded', 'message' => 'Daily AI limit reached — resets midnight Pacific (~3-4pm MYT), or enable billing.'];
            }
            $last = ['error' => 'provider_error', 'message' => $msg];
        }

        return $last;
    }

    /** @return array{status: int|null, body: mixed, error: string|null} */
    private function post(string $url, string $key, array $payload): array
    {
        try {
            $res = Http::timeout(60)->withHeaders(['x-goog-api-key' => $key])->post($url, $payload);

            return ['status' => $res->status(), 'body' => $res->json(), 'error' => null];
        } catch (\Throwable $e) {
            return ['status' => null, 'body' => null, 'error' => $e->getMessage()];
        }
    }

    /** Models to try for photo analysis (strong first, lite as quota fallback). */
    public static function visionModels(): array
    {
        $primary = config('calorielens.vision_model');
        $models = [$primary];
        if (! str_contains($primary, 'lite')) {
            $models[] = 'gemini-2.5-flash-lite';
        }

        return array_values(array_unique($models));
    }

    /** Convert a JSON-Schema subset to Gemini's responseSchema (drop min/max). */
    public static function toGeminiSchema(array $schema): array
    {
        unset($schema['minimum'], $schema['maximum']);
        if (isset($schema['items'])) {
            $schema['items'] = self::toGeminiSchema($schema['items']);
        }
        if (isset($schema['properties'])) {
            foreach ($schema['properties'] as $k => $child) {
                $schema['properties'][$k] = self::toGeminiSchema($child);
            }
        }

        return $schema;
    }
}
