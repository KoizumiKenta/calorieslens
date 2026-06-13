<?php

declare(strict_types=1);

namespace App\Http\Controllers\Api\V1;

use App\Domain\Diary\Actions\LogScanToDiary;
use App\Domain\Recognition\Actions\CorrectScanItem;
use App\Domain\Recognition\Actions\CreateScan;
use App\Http\Controllers\Controller;
use App\Http\Requests\CorrectScanItemRequest;
use App\Http\Requests\CreateScanRequest;
use App\Http\Requests\LogScanRequest;
use App\Http\Resources\ScanResource;
use App\Http\Resources\ScanResultItemResource;
use App\Jobs\ProcessMealPhotoJob;
use App\Models\MealScan;
use Illuminate\Http\JsonResponse;

final class ScanController extends Controller
{
    /**
     * POST /v1/scans — create scan, return signed upload URLs.
     * Cached barcodes resolve synchronously (no AI cost, instant UX).
     */
    public function store(CreateScanRequest $request, CreateScan $action): JsonResponse
    {
        $outcome = $action->handle($request->user(), $request->toDto());

        return response()->json(['data' => [
            'scan_id' => $outcome->scan->id,
            'status' => $outcome->scan->status,
            'upload_urls' => $outcome->uploadUrls,
            'depth_upload_url' => $outcome->depthUploadUrl,
            'result' => $outcome->syncResult ? new ScanResource($outcome->syncResult) : null,
        ]], 201);
    }

    /** POST /v1/scans/{scan}/complete-upload — enqueue the AI pipeline. */
    public function completeUpload(MealScan $scan): JsonResponse
    {
        $this->authorize('update', $scan);

        abort_unless(in_array($scan->status, ['pending', 'uploading'], true), 409, 'Scan already processed.');

        $scan->update(['status' => 'processing']);
        ProcessMealPhotoJob::dispatch($scan->id);

        return response()->json(status: 202);
    }

    /** GET /v1/scans/{scan} — poll fallback when WebSocket is unavailable. */
    public function show(MealScan $scan): ScanResource
    {
        $this->authorize('view', $scan);

        return new ScanResource($scan->load('latestResult.items'));
    }

    /**
     * PATCH /v1/scans/{scan}/items/{item} — user correction before logging.
     * Recomputes nutrition locally-cheap and emits EntryCorrected for the
     * personalization learner.
     */
    public function correctItem(
        CorrectScanItemRequest $request,
        MealScan $scan,
        string $item,
        CorrectScanItem $action,
    ): ScanResultItemResource {
        $this->authorize('update', $scan);

        return new ScanResultItemResource(
            $action->handle($scan, $item, $request->toDto()),
        );
    }

    /** POST /v1/scans/{scan}/log — one-call log of corrected result to diary. */
    public function logToDiary(LogScanRequest $request, MealScan $scan, LogScanToDiary $action): JsonResponse
    {
        $this->authorize('update', $scan);

        $entries = $action->handle(
            $scan,
            mealSlot: $request->validated('meal_slot'),
            entryDate: $request->date('entry_date'),
        );

        return response()->json(['data' => $entries], 201);
    }
}
