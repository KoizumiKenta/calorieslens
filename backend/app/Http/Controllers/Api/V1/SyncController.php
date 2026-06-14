<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\DiaryEntry;
use App\Models\Favorite;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Offline-first sync. The phone is the editor; it pushes local changes and
 * pulls everything changed since its last sync. Diary entries key on the
 * client UUID so re-pushes upsert (idempotent) and deletes ride along as
 * soft-delete tombstones. Volumes are tiny (one person's diary), so this
 * stays deliberately simple — last-write-wins, no operational transforms.
 */
class SyncController extends Controller
{
    /** GET /sync?since=ISO8601 — changes the client doesn't have yet. */
    public function pull(Request $request): JsonResponse
    {
        $user = $request->user();
        $since = $request->query('since');
        $sinceTs = $since ? Carbon::parse($since) : null;

        $entriesQuery = $user->diaryEntries()->withTrashed();
        if ($sinceTs) {
            $entriesQuery->where('updated_at', '>', $sinceTs);
        }

        $entries = $entriesQuery->get()->map(function (DiaryEntry $e) {
            return $e->toClientArray() + ['deleted' => $e->trashed()];
        });

        $favQuery = $user->favorites()->withTrashed();
        if ($sinceTs) {
            $favQuery->where('updated_at', '>', $sinceTs);
        }
        $favorites = $favQuery->get()->map(function (Favorite $f) {
            return $f->toClientArray() + ['deleted' => $f->trashed()];
        });

        return response()->json([
            'profile' => $user->profile,
            'diary_entries' => $entries,
            'favorites' => $favorites,
            'water' => $user->waterLogs()->get(['date_key', 'ml']),
            'weights' => $user->weightLogs()->get(['date_key', 'kg']),
            'server_time' => now()->toIso8601String(),
        ]);
    }

    /** POST /sync — apply the phone's local changes. */
    public function push(Request $request): JsonResponse
    {
        $data = $request->validate([
            'diary_entries' => ['array'],
            'diary_entries.*.id' => ['required', 'uuid'],
            'diary_entries.*.date_key' => ['required', 'string', 'max:10'],
            'diary_entries.*.meal' => ['required', 'in:breakfast,lunch,dinner,snack'],
            'diary_entries.*.food_name' => ['required', 'string', 'max:200'],
            'diary_entries.*.grams' => ['required', 'numeric'],
            'diary_entries.*.nutrition' => ['required', 'array'],
            'diary_entries.*.source' => ['nullable', 'string', 'max:20'],
            'diary_entries.*.emoji' => ['nullable', 'string', 'max:16'],
            'diary_entries.*.portion_label' => ['nullable', 'string', 'max:100'],
            'diary_entries.*.hydration_ml' => ['nullable', 'numeric'],
            'diary_entries.*.logged_at' => ['nullable', 'date'],
            'deleted_ids' => ['array'],
            'deleted_ids.*' => ['uuid'],
            'favorites' => ['array'],
            'favorites.*.id' => ['required', 'uuid'],
            'favorites.*.food_name' => ['required', 'string', 'max:200'],
            'favorites.*.emoji' => ['nullable', 'string', 'max:16'],
            'favorites.*.default_grams' => ['nullable', 'numeric'],
            'favorites.*.portion_label' => ['nullable', 'string', 'max:100'],
            'favorites.*.per_100g' => ['required', 'array'],
            'favorites.*.hydration_factor' => ['nullable', 'numeric'],
            'favorites.*.source' => ['nullable', 'string', 'max:20'],
            'deleted_favorite_ids' => ['array'],
            'deleted_favorite_ids.*' => ['uuid'],
            'water' => ['array'],
            'water.*.date_key' => ['required', 'string', 'max:10'],
            'water.*.ml' => ['required', 'integer', 'min:0'],
            'weights' => ['array'],
            'weights.*.date_key' => ['required', 'string', 'max:10'],
            'weights.*.kg' => ['required', 'numeric'],
        ]);

        $user = $request->user();

        DB::transaction(function () use ($user, $data) {
            foreach ($data['diary_entries'] ?? [] as $e) {
                $n = $e['nutrition'];
                $user->diaryEntries()->updateOrCreate(
                    ['id' => $e['id']],
                    [
                        'date_key' => $e['date_key'],
                        'meal' => $e['meal'],
                        'food_name' => $e['food_name'],
                        'grams' => $e['grams'],
                        'kcal' => $n['kcal'] ?? 0,
                        'protein_g' => $n['protein_g'] ?? 0,
                        'carbs_g' => $n['carbs_g'] ?? 0,
                        'fat_g' => $n['fat_g'] ?? 0,
                        'fiber_g' => $n['fiber_g'] ?? 0,
                        'sugar_g' => $n['sugar_g'] ?? 0,
                        'sodium_mg' => $n['sodium_mg'] ?? 0,
                        'source' => $e['source'] ?? 'search',
                        'emoji' => $e['emoji'] ?? '🍽️',
                        'portion_label' => $e['portion_label'] ?? null,
                        'hydration_ml' => $e['hydration_ml'] ?? 0,
                        'logged_at' => $e['logged_at'] ?? now(),
                        'deleted_at' => null, // a re-push revives a previously deleted id
                    ],
                );
            }

            if (! empty($data['deleted_ids'])) {
                $user->diaryEntries()->whereIn('id', $data['deleted_ids'])->delete();
            }

            foreach ($data['favorites'] ?? [] as $f) {
                $n = $f['per_100g'];
                $user->favorites()->updateOrCreate(
                    ['id' => $f['id']],
                    [
                        'food_name' => $f['food_name'],
                        'emoji' => $f['emoji'] ?? '🍽️',
                        'default_grams' => $f['default_grams'] ?? 100,
                        'portion_label' => $f['portion_label'] ?? null,
                        'kcal' => $n['kcal'] ?? 0,
                        'protein_g' => $n['protein_g'] ?? 0,
                        'carbs_g' => $n['carbs_g'] ?? 0,
                        'fat_g' => $n['fat_g'] ?? 0,
                        'fiber_g' => $n['fiber_g'] ?? 0,
                        'sugar_g' => $n['sugar_g'] ?? 0,
                        'sodium_mg' => $n['sodium_mg'] ?? 0,
                        'hydration_factor' => $f['hydration_factor'] ?? null,
                        'source' => $f['source'] ?? 'search',
                        'deleted_at' => null,
                    ],
                );
            }

            if (! empty($data['deleted_favorite_ids'])) {
                $user->favorites()->whereIn('id', $data['deleted_favorite_ids'])->delete();
            }

            foreach ($data['water'] ?? [] as $w) {
                $user->waterLogs()->updateOrCreate(
                    ['date_key' => $w['date_key']],
                    ['ml' => $w['ml']],
                );
            }

            foreach ($data['weights'] ?? [] as $w) {
                $user->weightLogs()->updateOrCreate(
                    ['date_key' => $w['date_key']],
                    ['kg' => $w['kg']],
                );
            }
        });

        return response()->json(['server_time' => now()->toIso8601String()]);
    }
}
