<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Gates the public AI endpoints (scan/estimate) with a shared secret so they
 * aren't free Gemini quota for the whole internet once the API is hosted.
 * Open when APP_TOKEN is unset (local dev).
 */
class EnsureAppToken
{
    public function handle(Request $request, Closure $next): Response
    {
        $expected = config('calorielens.app_token');
        if ($expected && ! hash_equals($expected, (string) $request->header('X-App-Token'))) {
            return response()->json([
                'error' => 'unauthorized',
                'message' => 'Missing or wrong X-App-Token header.',
            ], 401);
        }

        return $next($request);
    }
}
