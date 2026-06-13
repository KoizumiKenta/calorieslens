<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\Ai\FoodVisionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ScanController extends Controller
{
    public function __construct(private readonly FoodVisionService $vision) {}

    public function analyze(Request $request): JsonResponse
    {
        $data = $request->validate([
            'image' => ['required', 'string'],          // base64
            'media_type' => ['nullable', 'string'],
            'note' => ['nullable', 'string', 'max:300'],
        ]);

        if (base64_decode($data['image'], true) === false) {
            return response()->json(['error' => 'invalid_image', 'message' => 'image must be base64.'], 422);
        }
        $mediaType = in_array($data['media_type'] ?? '', ['image/jpeg', 'image/png', 'image/webp', 'image/gif'], true)
            ? $data['media_type'] : 'image/jpeg';

        $result = $this->vision->analyze($data['image'], $mediaType, $data['note'] ?? '');

        return response()->json($result, isset($result['error']) ? 502 : 200);
    }

    public function refine(Request $request): JsonResponse
    {
        $data = $request->validate([
            'item' => ['required', 'array'],
            'note' => ['required', 'string', 'min:1', 'max:500'],
        ]);

        $result = $this->vision->refine($data['item'], $data['note']);

        return response()->json(
            isset($result['error']) ? $result : ['item' => $result],
            isset($result['error']) ? 502 : 200,
        );
    }
}
