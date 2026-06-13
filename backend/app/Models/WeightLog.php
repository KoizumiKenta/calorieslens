<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** A weigh-in (kg). One row per user per date_key (latest wins). */
class WeightLog extends Model
{
    protected $fillable = ['date_key', 'kg'];

    protected function casts(): array
    {
        return ['kg' => 'float'];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
