<?php

declare(strict_types=1);

namespace App\Jobs;

use App\Domain\AI\AIManager;
use App\Domain\AI\DTO\VisionRequest;
use App\Domain\Recognition\FoodRecognitionPipeline;
use App\Events\ScanReady;
use App\Models\MealScan;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Context;
use Illuminate\Support\Facades\Storage;

/**
 * The core loop: photo → vision → decomposition → portions → nutrition →
 * persisted ScanResult → websocket push (docs/02-architecture.md §3).
 * Idempotent per scan; safe to retry.
 */
final class ProcessMealPhotoJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 3;

    /** @var int[] */
    public array $backoff = [5, 15, 60];

    public function __construct(public readonly string $scanId) {}

    public function viaQueue(): string
    {
        return 'ai-vision';
    }

    public function handle(AIManager $ai, FoodRecognitionPipeline $pipeline): void
    {
        $scan = MealScan::findOrFail($this->scanId);

        if ($scan->status === 'ready') {
            return; // idempotency: a previous attempt already finished
        }

        Context::add('user_id', $scan->user_id);
        $scan->update(['status' => 'processing']);

        // Stage 1 — preprocess: validate, normalize, dedupe, scale hints
        $prepared = $pipeline->preprocess($scan);

        if ($prepared->dedupedResultId !== null) {
            // Same plate scanned minutes ago (perceptual hash) — reuse, zero AI cost
            $scan->update(['status' => 'ready', 'completed_at' => now()]);
            ScanReady::dispatch($scan->user_id, $scan->id, $prepared->dedupedResultId);

            return;
        }

        // Stages 2–3 — vision detection + composite decomposition
        $analysis = $ai->vision(new VisionRequest(
            images: $prepared->images,
            locale: $scan->user->locale,
            localeDishVocabulary: $pipeline->dishVocabularyFor($scan->user->locale),
            depthMapPng: $scan->depth_map_key
                ? Storage::disk('media')->get($scan->depth_map_key)
                : null,
            beforeItems: $pipeline->beforeItemsFor($scan),
            difficulty: $prepared->difficulty,
        ));

        // Stages 4–6 — portion fusion, nutrition resolution, persist + range math
        $result = $pipeline->compose($scan, $analysis);

        $scan->update(['status' => 'ready', 'completed_at' => now()]);

        ScanReady::dispatch($scan->user_id, $scan->id, $result->id);
    }

    public function failed(\Throwable $e): void
    {
        MealScan::where('id', $this->scanId)->update([
            'status' => 'failed',
            'error_code' => $e instanceof \App\Domain\AI\Exceptions\AllProvidersFailedException
                ? 'providers_unavailable'
                : 'processing_error',
        ]);
        // Client shows the search-fallback CTA on scan.failed
        ScanReady::dispatch(MealScan::find($this->scanId)?->user_id, $this->scanId, null);
    }
}
