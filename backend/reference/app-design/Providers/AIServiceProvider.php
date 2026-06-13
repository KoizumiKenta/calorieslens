<?php

declare(strict_types=1);

namespace App\Providers;

use App\Domain\AI\AIManager;
use App\Domain\AI\Providers\Vision\ClaudeVisionProvider;
use App\Domain\AI\Providers\Vision\GeminiVisionProvider;
use App\Domain\AI\Providers\Vision\OpenAIVisionProvider;
use App\Domain\AI\Resilience\CircuitBreaker;
use App\Domain\AI\Resilience\FallbackChain;
use App\Domain\AI\Resilience\UsageRecorder;
use App\Domain\Nutrition\InternalFoodSource;
use App\Domain\Nutrition\NutritionResolver;
use App\Domain\Nutrition\NutritionValidator;
use App\Domain\Nutrition\Sources\UsdaFoodDataSource;
use Illuminate\Support\ServiceProvider;

final class AIServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(CircuitBreaker::class, fn ($app) => new CircuitBreaker(
            cache: $app['cache']->store('redis'),
            events: $app['events'],
            failureThreshold: config('ai.circuit_breaker.failure_threshold'),
            windowSeconds: config('ai.circuit_breaker.window_seconds'),
            cooldownSeconds: config('ai.circuit_breaker.cooldown_seconds'),
        ));

        $this->app->singleton(FallbackChain::class);
        $this->app->singleton(UsageRecorder::class);

        $this->app->singleton(AIManager::class, fn ($app) => new AIManager(
            container: $app,
            chain: $app->make(FallbackChain::class),
            config: config('ai'),
        ));

        // Container keys follow "ai.{capability}.{provider}" — AIManager
        // resolves chains lazily from these bindings (config-driven order)
        $timeout = (int) config('ai.capabilities.vision.timeout_seconds');

        $this->app->bind('ai.vision.openai', fn () => new OpenAIVisionProvider(
            apiKey: config('ai.providers.openai.api_key'),
            model: config('ai.providers.openai.vision_model'),
            timeoutSeconds: $timeout,
        ));
        $this->app->bind('ai.vision.gemini', fn () => new GeminiVisionProvider(
            apiKey: config('ai.providers.gemini.api_key'),
            model: config('ai.providers.gemini.vision_model'),
            timeoutSeconds: $timeout,
        ));
        $this->app->bind('ai.vision.claude', fn () => new ClaudeVisionProvider(
            apiKey: config('ai.providers.claude.api_key'),
            model: config('ai.providers.claude.vision_model'),
            timeoutSeconds: $timeout,
        ));

        // OCR / STT / chat / embedding adapters bind the same way:
        //   ai.ocr.google_vision, ai.ocr.textract, ai.ocr.tesseract,
        //   ai.stt.whisper, ai.stt.google_stt,
        //   ai.chat.claude, ai.chat.openai, ai.chat.gemini, ai.embedding.openai

        $this->app->singleton(NutritionResolver::class, fn ($app) => new NutritionResolver(
            internal: $app->make(InternalFoodSource::class),
            externalSources: [
                $app->make(UsdaFoodDataSource::class),
                // OpenFoodFactsSource, NutritionixSource, EdamamSource,
                // SpoonacularSource — registered in priority order (docs/07 §5)
            ],
            validator: $app->make(NutritionValidator::class),
            cache: $app['cache']->store('redis'),
        ));

        $this->app->when(UsdaFoodDataSource::class)
            ->needs('$apiKey')
            ->giveConfig('services.usda.key');
    }
}
