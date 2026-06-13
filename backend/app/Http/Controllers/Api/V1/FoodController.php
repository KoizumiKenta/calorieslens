<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Food;
use App\Services\Food\AiEstimateSource;
use App\Services\Food\FoodSearchService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

class FoodController extends Controller
{
    public function __construct(private readonly FoodSearchService $search) {}

    public function index(Request $request): JsonResponse
    {
        $q = (string) $request->query('q', '');
        $results = $this->search->search($q);

        return response()->json([
            'query' => $q,
            'results' => $results->map(fn (Food $f) => $f->toClientArray())->values(),
        ]);
    }

    /**
     * "Estimate any dish with AI" — for local foods no database carries.
     * Cached by slug so the same dish is only estimated once.
     */
    public function estimate(Request $request, AiEstimateSource $ai): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'min:2', 'max:120'],
        ]);
        $name = trim($data['name']);
        $slug = Str::slug($name);

        $cached = Food::where('external_id', $slug)
            ->whereIn('source', ['ai', 'curated'])
            ->first();
        if ($cached) {
            return response()->json(['food' => $cached->toClientArray(), 'cached' => true]);
        }

        $row = $ai->estimate($name);
        if ($row === null) {
            return response()->json([
                'error' => 'estimate_failed',
                'message' => "Couldn't estimate \"{$name}\" right now. Try the camera scan instead.",
            ], 502);
        }

        $food = Food::updateOrCreate(
            ['source' => $row['source'], 'external_id' => $row['external_id']],
            $row,
        );

        return response()->json(['food' => $food->toClientArray(), 'cached' => false]);
    }
}
