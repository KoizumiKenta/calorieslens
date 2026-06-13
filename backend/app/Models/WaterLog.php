<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Manual water tally per day (ml). One row per user per date_key. */
class WaterLog extends Model
{
    protected $fillable = ['date_key', 'ml'];

    protected function casts(): array
    {
        return ['ml' => 'integer'];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
