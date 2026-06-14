<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\CoachController;
use App\Http\Controllers\Api\V1\FoodController;
use App\Http\Controllers\Api\V1\ProfileController;
use App\Http\Controllers\Api\V1\ScanController;
use App\Http\Controllers\Api\V1\SyncController;
use Illuminate\Support\Facades\Route;

/*
 * CalorieLens API v1 — accounts + offline-first sync.
 * (The fuller route map — scans, foods, coach, planner — is preserved in
 * reference/api-routes-design.php as the build-out target.)
 */
Route::prefix('v1')->group(function () {
    Route::post('auth/register', [AuthController::class, 'register']);
    Route::post('auth/login', [AuthController::class, 'login']);

    // Food search is public (anyone can search before signing in) but rate-limited.
    Route::middleware('throttle:60,1')->get('foods/search', [FoodController::class, 'index']);
    // Barcode lookup (Open Food Facts), public + rate-limited.
    Route::middleware('throttle:60,1')->get('foods/barcode/{code}', [FoodController::class, 'barcode']);
    // AI estimate costs provider quota — tighter limit.
    Route::middleware('throttle:20,1')->post('foods/estimate', [FoodController::class, 'estimate']);

    // AI photo analysis — public but app-token gated (shared Gemini quota).
    Route::middleware(['app.token', 'throttle:30,1'])->group(function () {
        Route::post('scans/analyze', [ScanController::class, 'analyze']);
        Route::post('scans/refine', [ScanController::class, 'refine']);
    });

    // AI nutrition coach — app-token gated (shared Gemini quota).
    Route::middleware(['app.token', 'throttle:20,1'])->group(function () {
        Route::post('coach/messages', [CoachController::class, 'messages']);
    });

    Route::middleware('auth:sanctum')->group(function () {
        Route::post('auth/logout', [AuthController::class, 'logout']);
        Route::get('me', [AuthController::class, 'me']);
        Route::put('profile', [ProfileController::class, 'update']);
        Route::get('sync', [SyncController::class, 'pull']);
        Route::post('sync', [SyncController::class, 'push']);
    });
});
