<?php

declare(strict_types=1);

use App\Http\Controllers\Api\V1;
use Illuminate\Support\Facades\Route;

/*
 * API v1. Matches docs/04-api/openapi.yaml — CI diff-checks the two.
 * Middleware: auth:api = JWT guard; quota:* = Redis sliding-window tier
 * quotas (config/ai.php); idempotency = Idempotency-Key replay store.
 */

Route::prefix('v1')->group(function (): void {

    // ---- Auth (throttled hard; see docs/08-security.md §1)
    Route::prefix('auth')->middleware('throttle:auth')->group(function (): void {
        Route::post('register', [V1\AuthController::class, 'register']);
        Route::post('login', [V1\AuthController::class, 'login']);
        Route::post('refresh', [V1\AuthController::class, 'refresh']);
        Route::post('logout', [V1\AuthController::class, 'logout'])->middleware('auth:api');
    });

    Route::middleware(['auth:api', 'throttle:api'])->group(function (): void {

        // ---- Scans: every AI capture mode
        Route::prefix('scans')->group(function (): void {
            Route::post('/', [V1\ScanController::class, 'store'])
                ->middleware(['quota:scans', 'idempotency']);
            Route::post('{scan}/complete-upload', [V1\ScanController::class, 'completeUpload']);
            Route::get('{scan}', [V1\ScanController::class, 'show']);
            Route::patch('{scan}/items/{item}', [V1\ScanController::class, 'correctItem']);
            Route::post('{scan}/items', [V1\ScanController::class, 'addItem']);
            Route::post('{scan}/log', [V1\ScanController::class, 'logToDiary']);
        });

        // ---- Foods
        Route::get('foods/search', [V1\FoodController::class, 'search'])->middleware('throttle:search');
        Route::get('foods/barcode/{code}', [V1\FoodController::class, 'barcode']);
        Route::get('foods/{food}', [V1\FoodController::class, 'show']);
        Route::post('foods/custom', [V1\FoodController::class, 'storeCustom']);
        Route::post('foods/submissions', [V1\FoodSubmissionController::class, 'store']);

        // ---- Diary
        Route::get('diary', [V1\DiaryController::class, 'day']);
        Route::post('diary/entries', [V1\DiaryController::class, 'store'])->middleware('idempotency');
        Route::patch('diary/entries/{entry}', [V1\DiaryController::class, 'update']);
        Route::delete('diary/entries/{entry}', [V1\DiaryController::class, 'destroy']);
        Route::apiResource('favorites', V1\FavoriteController::class)->only(['index', 'store', 'destroy']);
        Route::apiResource('templates', V1\MealTemplateController::class)->only(['index', 'store', 'destroy']);
        Route::post('templates/{template}/log', [V1\MealTemplateController::class, 'log']);

        // ---- Tracking
        Route::get('weights', [V1\WeightController::class, 'index']);
        Route::post('weights', [V1\WeightController::class, 'store']);
        Route::post('water', [V1\WaterController::class, 'store']);
        Route::post('exercises', [V1\ExerciseController::class, 'store']);
        Route::post('health/sync', [V1\HealthSyncController::class, 'store']);
        Route::get('dashboard', [V1\DashboardController::class, 'show']);

        // ---- Coach
        Route::post('coach/messages', [V1\CoachController::class, 'send'])->middleware('quota:coach');
        Route::get('coach/insights', [V1\CoachController::class, 'insights']);

        // ---- Planner (premium)
        Route::post('planner/plans', [V1\PlannerController::class, 'store'])
            ->middleware('tier:premium,family,enterprise');

        // ---- Profile
        Route::get('me', [V1\MeController::class, 'show']);
        Route::patch('me', [V1\MeController::class, 'update']);
        Route::post('me/export', [V1\MeController::class, 'export']);
        Route::post('me/delete', [V1\MeController::class, 'requestDeletion']);
    });
});
