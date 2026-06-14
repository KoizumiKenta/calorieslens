<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Food;
use App\Services\Food\AiEstimateSource;
use App\Services\Food\FoodSearchService;
use App\Services\Food\OpenFoodFactsSource;
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
     * Barcode lookup (EAN/UPC) via Open Food Facts. Cached into the foods
     * table on first hit, so a re-scan is instant and it shows up in search.
     */
    public function barcode(string $code, OpenFoodFactsSource $off): JsonResponse
    {
        $code = preg_replace('/\D/', '', $code);
        if (strlen($code) < 6 || strlen($code) > 14) {
            return response()->json(
                ['error' => 'invalid_barcode', 'message' => 'That barcode looks wrong.'],
                422,
            );
        }

        $cached = Food::where('source', 'off')->where('external_id', $code)->first();
        if ($cached) {
            return response()->json(['food' => $cached->toClientArray(), 'cached' => true]);
        }

        $row = $off->lookupByBarcode($code);
        if ($row === null) {
            return response()->json([
                'error' => 'not_found',
                'message' => "No product found for that barcode. Add it as a custom food.",
            ], 404);
        }

        $food = Food::updateOrCreate(
            ['source' => $row['source'], 'external_id' => $row['external_id']],
            $row,
        );

        return response()->json(['food' => $food->toClientArray(), 'cached' => false]);
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
