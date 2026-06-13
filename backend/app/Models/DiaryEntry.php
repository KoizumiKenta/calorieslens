<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * One logged food. The primary key IS the client's UUID — that makes sync
 * idempotent (re-pushing the same entry upserts, never duplicates) and lets
 * deletes propagate as soft-delete tombstones the client can pull.
 *
 * Nutrition is stored as columns (a snapshot taken at log time, like the
 * Flutter model) so history is immutable and queryable.
 */
class DiaryEntry extends Model
{
    use SoftDeletes;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'id', 'date_key', 'meal', 'food_name', 'grams',
        'kcal', 'protein_g', 'carbs_g', 'fat_g', 'fiber_g', 'sugar_g', 'sodium_mg',
        'source', 'emoji', 'portion_label', 'hydration_ml', 'logged_at',
    ];

    protected function casts(): array
    {
        return [
            'grams' => 'float',
            'kcal' => 'float',
            'protein_g' => 'float',
            'carbs_g' => 'float',
            'fat_g' => 'float',
            'fiber_g' => 'float',
            'sugar_g' => 'float',
            'sodium_mg' => 'float',
            'hydration_ml' => 'float',
            'logged_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** Shape the client (mobile/lib/core/models/diary_entry.dart) expects. */
    public function toClientArray(): array
    {
        return [
            'id' => $this->id,
            'date_key' => $this->date_key,
            'meal' => $this->meal,
            'food_name' => $this->food_name,
            'grams' => $this->grams,
            'nutrition' => [
                'kcal' => $this->kcal,
                'protein_g' => $this->protein_g,
                'carbs_g' => $this->carbs_g,
                'fat_g' => $this->fat_g,
                'fiber_g' => $this->fiber_g,
                'sugar_g' => $this->sugar_g,
                'sodium_mg' => $this->sodium_mg,
            ],
            'source' => $this->source,
            'logged_at' => optional($this->logged_at)->toIso8601String(),
            'emoji' => $this->emoji,
            'portion_label' => $this->portion_label,
            'hydration_ml' => $this->hydration_ml,
        ];
    }
}
