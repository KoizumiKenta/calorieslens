<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUuids;
use Illuminate\Database\Eloquent\Model;

class Food extends Model
{
    use HasUuids;

    protected $table = 'foods'; // "Food" is uncountable; pin it explicitly

    protected $fillable = [
        'source', 'external_id', 'name', 'brand', 'region', 'emoji',
        'kcal', 'protein_g', 'carbs_g', 'fat_g', 'fiber_g', 'sugar_g', 'sodium_mg',
        'portions', 'aliases', 'hydration_factor', 'verified', 'popularity',
    ];

    protected function casts(): array
    {
        return [
            'kcal' => 'float', 'protein_g' => 'float', 'carbs_g' => 'float',
            'fat_g' => 'float', 'fiber_g' => 'float', 'sugar_g' => 'float',
            'sodium_mg' => 'float', 'hydration_factor' => 'float',
            'portions' => 'array', 'aliases' => 'array', 'verified' => 'boolean',
        ];
    }

    /** The shape the Flutter Food model parses. */
    public function toClientArray(): array
    {
        return [
            'id' => $this->id,
            'name' => $this->name,
            'brand' => $this->brand,
            'region' => $this->region,
            'emoji' => $this->emoji,
            'source' => $this->source,
            'per_100g' => [
                'kcal' => $this->kcal,
                'protein_g' => $this->protein_g,
                'carbs_g' => $this->carbs_g,
                'fat_g' => $this->fat_g,
                'fiber_g' => $this->fiber_g,
                'sugar_g' => $this->sugar_g,
                'sodium_mg' => $this->sodium_mg,
            ],
            'portions' => $this->portions ?? [],
            'aliases' => $this->aliases ?? [],
            'hydration_factor' => $this->hydration_factor,
        ];
    }
}
