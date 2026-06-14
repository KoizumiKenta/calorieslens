<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * A starred food the user can re-log in one tap. PK is the client UUID so sync
 * is idempotent and deletes propagate as tombstones, same as DiaryEntry. Stores
 * the per-100g snapshot needed to recreate a diary entry without a DB lookup.
 */
class Favorite extends Model
{
    use SoftDeletes;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id', 'food_name', 'emoji', 'default_grams', 'portion_label',
        'kcal', 'protein_g', 'carbs_g', 'fat_g', 'fiber_g', 'sugar_g', 'sodium_mg',
        'hydration_factor', 'source',
    ];

    protected function casts(): array
    {
        return [
            'default_grams' => 'float',
            'kcal' => 'float',
            'protein_g' => 'float',
            'carbs_g' => 'float',
            'fat_g' => 'float',
            'fiber_g' => 'float',
            'sugar_g' => 'float',
            'sodium_mg' => 'float',
            'hydration_factor' => 'float',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** Shape the client (mobile favorites repo) expects. */
    public function toClientArray(): array
    {
        return [
            'id' => $this->id,
            'food_name' => $this->food_name,
            'emoji' => $this->emoji,
            'default_grams' => $this->default_grams,
            'portion_label' => $this->portion_label,
            'per_100g' => [
                'kcal' => $this->kcal,
                'protein_g' => $this->protein_g,
                'carbs_g' => $this->carbs_g,
                'fat_g' => $this->fat_g,
                'fiber_g' => $this->fiber_g,
                'sugar_g' => $this->sugar_g,
                'sodium_mg' => $this->sodium_mg,
            ],
            'hydration_factor' => $this->hydration_factor,
            'source' => $this->source,
        ];
    }
}
