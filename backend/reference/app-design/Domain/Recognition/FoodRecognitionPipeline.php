<?php

declare(strict_types=1);

namespace App\Domain\Recognition;

use App\Domain\AI\DTO\DetectedItem;
use App\Domain\AI\DTO\VisionAnalysis;
use App\Domain\Nutrition\NutritionResolver;
use App\Domain\Personalization\PriorStore;
use App\Domain\Recognition\DTO\PreparedScan;
use App\Models\MealScan;
use App\Models\ScanResult;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Intervention\Image\Laravel\Facades\Image;

/**
 * Orchestrates the non-AI stages of recognition (docs/02 §3). The vision
 * call itself happens in ProcessMealPhotoJob via AIManager — this class is
 * fully deterministic and unit-testable with a fixed VisionAnalysis.
 */
final class FoodRecognitionPipeline
{
    public function __construct(
        private readonly NutritionResolver $nutrition,
        private readonly PortionEstimator $portions,
        private readonly PriorStore $priors,
        private readonly CookingModifierTable $cookingModifiers,
    ) {}

    /** Stage 1: validate/normalize media, dedupe, compute difficulty for routing. */
    public function preprocess(MealScan $scan): PreparedScan
    {
        $images = [];
        $phashes = [];

        foreach ($scan->mediaObjects as $media) {
            $raw = Storage::disk('media')->get($media->storage_key);

            // Re-encode through the image library: strips EXIF (again) and
            // neutralizes malformed/polyglot files (docs/08 §3)
            $img = Image::read($raw)->scaleDown(width: 1536, height: 1536);
            $images[] = ['bytes' => $img->toJpeg(82)->toString(), 'mime' => 'image/jpeg',
                'angle' => $media->meta['angle'] ?? null];
            $phashes[] = $media->phash;
        }

        $dedupedResultId = $this->findRecentDuplicate($scan->user_id, $phashes);

        return new PreparedScan(
            images: $images,
            dedupedResultId: $dedupedResultId,
            difficulty: $this->estimateDifficulty($scan),
        );
    }

    /** Stages 4–6: portions, nutrition, totals; persists and returns the result. */
    public function compose(MealScan $scan, VisionAnalysis $analysis): ScanResult
    {
        return DB::transaction(function () use ($scan, $analysis) {
            $result = ScanResult::create([
                'scan_id' => $scan->id,
                'provider' => $analysis->provider,
                'model' => $analysis->model,
                'reasoning' => $analysis->mealReasoning,
                'raw_response' => null, // populated by debug flag only
                'latency_ms' => $analysis->latencyMs,
                'cost_usd' => $analysis->costUsd,
            ]);

            $itemRows = [];
            foreach ($analysis->items as $detected) {
                $itemRows = [...$itemRows, ...$this->composeItem($scan, $result, $detected, $analysis, parentRowId: null)];
            }

            $kcalRange = $this->portions->mealKcalRange(array_map(
                static fn (array $r) => ['kcal' => $r['kcal'], 'kcal_low' => $r['kcal_low'], 'kcal_high' => $r['kcal_high']],
                $itemRows,
            ));

            $confidences = array_column($itemRows, 'confidence');

            $result->update([
                'total_kcal' => array_sum(array_column($itemRows, 'kcal')),
                'kcal_low' => $kcalRange['low'],
                'kcal_high' => $kcalRange['high'],
                'confidence' => $confidences === [] ? 0 : round(array_sum($confidences) / count($confidences), 3),
            ]);

            return $result->refresh();
        });
    }

    /**
     * Resolve one detected item (recursing into composite components) into
     * persisted scan_result_items rows. Returns flat row data for range math.
     */
    private function composeItem(
        MealScan $scan,
        ScanResult $result,
        DetectedItem $detected,
        VisionAnalysis $analysis,
        ?string $parentRowId,
    ): array {
        // Composite dish: persist the parent as a zero-nutrition grouping node,
        // nutrition lives on the components users actually edit
        if ($detected->isComposite && $detected->components !== []) {
            $parent = $result->items()->create([
                'detected_label' => $detected->label,
                'grams' => $detected->portion['grams'],
                'kcal' => 0,
                'confidence' => $detected->confidence,
                'reasoning' => $detected->reasoning,
                'bbox' => $detected->bbox,
            ]);

            $rows = [];
            foreach ($detected->components as $component) {
                $rows = [...$rows, ...$this->composeItem($scan, $result, $component, $analysis, $parent->id)];
            }

            return $rows;
        }

        $resolved = $this->nutrition->resolve($detected->label, $scan->user->locale);

        $portion = $this->portions->estimate(
            item: $detected,
            scaleHintPxPerMm: $analysis->scaleHint(),
            depthVolumeMl: null, // depth volume integration lands with CAP-6
            densityGPerMl: null,
            userPrior: $resolved?->foodItemId
                ? $this->priors->portionBias($scan->user_id, $resolved->foodItemId)
                : null,
        );

        $per100g = $resolved?->per100g ?? $this->fallbackNutrition($detected);
        $facts = $this->cookingModifiers->apply(
            $per100g->scaledFromPer100g($portion['grams']),
            $detected->cookingMethod,
            $portion['grams'],
        );

        $row = $result->items()->create([
            'food_item_id' => $resolved?->foodItemId,
            'detected_label' => $detected->label,
            'component_of' => $parentRowId,
            'grams' => $portion['grams'],
            'grams_low' => $portion['low'],
            'grams_high' => $portion['high'],
            'serving_label' => $detected->portion['serving_label'],
            'cooking_method' => $detected->cookingMethod,
            'kcal' => $facts->kcal,
            'protein_g' => $facts->proteinG,
            'carbs_g' => $facts->carbsG,
            'fat_g' => $facts->fatG,
            'fiber_g' => $facts->fiberG,
            'sugar_g' => $facts->sugarG,
            'sodium_mg' => $facts->sodiumMg,
            'confidence' => $detected->confidence,
            'portion_confidence' => $portion['confidence'],
            'reasoning' => $detected->reasoning,
            'bbox' => $detected->bbox,
            'consumed_fraction' => $detected->remainingFraction !== null
                ? round(1.0 - $detected->remainingFraction, 3)
                : null,
        ]);

        $kcalPerGram = $portion['grams'] > 0 ? $facts->kcal / $portion['grams'] : 0;

        return [[
            'id' => $row->id,
            'kcal' => $facts->kcal,
            'kcal_low' => $portion['low'] * $kcalPerGram,
            'kcal_high' => $portion['high'] * $kcalPerGram,
            'confidence' => $detected->confidence,
        ]];
    }

    public function dishVocabularyFor(string $locale): array
    {
        return cache()->remember("dish-vocab:{$locale}", 3600, static fn () => DB::table('food_items')
            ->where('locale_origin', strtoupper($locale === 'ms' ? 'MY' : $locale))
            ->where('is_composite', true)
            ->orderByDesc('popularity')
            ->limit(60)
            ->pluck('canonical_name')
            ->all());
    }

    public function beforeItemsFor(MealScan $scan): ?array
    {
        if ($scan->kind !== 'before_after' || $scan->parent_scan_id === null) {
            return null;
        }

        return ScanResult::where('scan_id', $scan->parent_scan_id)
            ->latest()->first()
            ?->items()->whereNull('component_of')
            ->get(['id', 'detected_label', 'grams'])
            ->toArray();
    }

    private function findRecentDuplicate(string $userId, array $phashes): ?string
    {
        foreach (array_filter($phashes) as $phash) {
            if ($resultId = cache()->get("phash:{$userId}:{$phash}")) {
                return $resultId;
            }
        }

        return null;
    }

    private function estimateDifficulty(MealScan $scan): float
    {
        // Cheap-model routing heuristic: multi-image and before/after scans
        // are harder; single clear photos route cheap (docs/07 §9)
        return match (true) {
            $scan->kind === 'before_after' => 0.9,
            count($scan->media_ids) > 1 => 0.7,
            default => 0.4,
        };
    }

    private function fallbackNutrition(DetectedItem $detected): \App\Domain\Shared\NutritionFacts
    {
        // No source resolved the label: category-average tables keep the UX
        // moving; the item is flagged low-confidence so the user verifies
        return CategoryAverages::for($detected->categoryHint);
    }
}
