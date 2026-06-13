<?php

declare(strict_types=1);

/*
 * AI capability configuration. Provider order IS the fallback chain —
 * reorder here to change arbitrage, never in code. Benchmarked per release
 * by the provider scorecard job (docs/07-ai-services.md §8).
 */
return [

    'capabilities' => [
        'vision' => [
            'chain' => ['gemini', 'openai', 'claude'],
            'timeout_seconds' => 20,
            'retries' => 2,
        ],
        'ocr' => [
            'chain' => ['google_vision', 'textract', 'tesseract'],
            'timeout_seconds' => 15,
            'retries' => 2,
        ],
        'stt' => [
            'chain' => ['whisper', 'google_stt'],
            'timeout_seconds' => 30,
            'retries' => 1,
        ],
        'chat' => [
            'chain' => ['claude', 'openai', 'gemini'],
            'timeout_seconds' => 60,
            'first_token_timeout_seconds' => 4,
            'retries' => 1,
        ],
        'embedding' => [
            'chain' => ['openai'],
            'timeout_seconds' => 10,
            'retries' => 2,
        ],
    ],

    'providers' => [
        'openai' => [
            'api_key' => env('OPENAI_API_KEY'),
            'vision_model' => env('OPENAI_VISION_MODEL', 'gpt-5.2'),
            'chat_model' => env('OPENAI_CHAT_MODEL', 'gpt-5.2'),
            'embedding_model' => 'text-embedding-3-small',
        ],
        'gemini' => [
            'api_key' => env('GEMINI_API_KEY'),
            'vision_model' => env('GEMINI_VISION_MODEL', 'gemini-3-pro'),
        ],
        'claude' => [
            'api_key' => env('ANTHROPIC_API_KEY'),
            'vision_model' => env('CLAUDE_VISION_MODEL', 'claude-fable-5'),
            'chat_model' => env('CLAUDE_CHAT_MODEL', 'claude-fable-5'),
        ],
        'google_vision' => ['credentials' => env('GOOGLE_APPLICATION_CREDENTIALS')],
        'textract' => ['region' => env('AWS_DEFAULT_REGION', 'ap-southeast-1')],
        'tesseract' => ['endpoint' => env('TESSERACT_SERVICE_URL', 'http://ocr-tesseract:8884')],
        'whisper' => ['api_key' => env('OPENAI_API_KEY')],
        'google_stt' => ['credentials' => env('GOOGLE_APPLICATION_CREDENTIALS')],
    ],

    'circuit_breaker' => [
        'failure_threshold' => 5,     // failures within window to open
        'window_seconds' => 60,
        'cooldown_seconds' => 60,     // open → half-open probe interval
    ],

    /*
     * Model routing: send easy cases to the cheap tier (docs/07 §9).
     * Pipeline computes a difficulty score from image quality + dish class.
     */
    'routing' => [
        'cheap_tier_max_difficulty' => 0.35,
        'cheap_models' => [
            'gemini' => 'gemini-3-flash',
            'openai' => 'gpt-5.2-mini',
            'claude' => 'claude-haiku-4-5-20251001',
        ],
    ],

    'quotas' => [
        // per-day, enforced by QuotaMiddleware (Redis sliding window)
        'free' => ['photo_scans' => 5, 'voice_logs' => 3, 'coach_messages' => 10],
        'premium' => ['photo_scans' => 200, 'voice_logs' => 100, 'coach_messages' => 300],
        'family' => ['photo_scans' => 200, 'voice_logs' => 100, 'coach_messages' => 300],
        'enterprise' => ['photo_scans' => 500, 'voice_logs' => 200, 'coach_messages' => 500],
    ],

    'media' => [
        'max_upload_bytes' => 10 * 1024 * 1024,
        'max_dimension_px' => 1536,
        'purge_after_hours' => 24,            // unless users.keep_photos
        'raw_response_retention_days' => 7,
    ],
];
