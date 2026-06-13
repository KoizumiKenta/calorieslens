<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Mirrors the Flutter UserProfile (mobile/lib/core/models/user_profile.dart).
 * Calorie/macro targets are derived client-side from these fields, so the
 * server only persists the inputs — one source of truth for the formula.
 */
class Profile extends Model
{
    protected $fillable = [
        'name', 'sex', 'age', 'height_cm', 'weight_kg', 'activity', 'goal',
    ];

    protected function casts(): array
    {
        return [
            'age' => 'integer',
            'height_cm' => 'float',
            'weight_kg' => 'float',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
