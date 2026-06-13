<?php

// Read via config() (not env()) everywhere so `php artisan config:cache`
// works in production — env() returns null once config is cached.
return [
    'gemini_key' => env('GEMINI_API_KEY'),

    // Vision prefers the stronger model; lite is the quota fallback.
    'vision_model' => env('CALORIELENS_VISION_MODEL', 'gemini-2.5-flash'),
    'text_model' => env('CALORIELENS_MODEL', 'gemini-2.5-flash-lite'),

    // Shared secret for the public AI endpoints (scan/estimate). Empty = open.
    'app_token' => env('APP_TOKEN'),
];
