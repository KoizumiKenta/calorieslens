<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Services\Ai\CoachService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CoachController extends Controller
{
    public function __construct(private readonly CoachService $coach) {}

    public function messages(Request $request): JsonResponse
    {
        $data = $request->validate([
            'message' => ['required', 'string', 'min:1', 'max:1000'],
            'context' => ['nullable', 'string', 'max:2000'],
            'history' => ['nullable', 'array', 'max:10'],
            'history.*.role' => ['required_with:history', 'string', 'in:user,coach'],
            'history.*.text' => ['required_with:history', 'string', 'max:2000'],
        ]);

        $result = $this->coach->reply(
            $data['message'],
            $data['context'] ?? 'No tracking data provided.',
            $data['history'] ?? [],
        );

        return response()->json($result, isset($result['error']) ? 502 : 200);
    }
}
