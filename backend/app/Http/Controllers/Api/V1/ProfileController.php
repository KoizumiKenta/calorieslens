<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ProfileController extends Controller
{
    public function update(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:100'],
            'sex' => ['required', 'in:male,female'],
            'age' => ['required', 'integer', 'min:13', 'max:120'],
            'height_cm' => ['required', 'numeric', 'min:80', 'max:260'],
            'weight_kg' => ['required', 'numeric', 'min:25', 'max:400'],
            'activity' => ['required', 'in:sedentary,light,moderate,active,veryActive'],
            'goal' => ['required', 'in:lose,maintain,gain'],
        ]);

        $profile = $request->user()->profile()->updateOrCreate([], $data);

        return response()->json(['profile' => $profile]);
    }
}
