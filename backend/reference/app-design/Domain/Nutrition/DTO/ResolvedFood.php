<?php

declare(strict_types=1);

namespace App\Domain\Nutrition\DTO;

use App\Domain\Shared\NutritionFacts;

final readonly class ResolvedFood
{
    public function __construct(
        public string $name,
        public NutritionFacts $per100g,
        public string $source,            // internal|usda|off|nutritionix|edamam|spoonacular
        public ?string $sourceRef,
        public ?string $foodItemId,       // set when resolved against internal DB
        public ?string $brand = null,
        public ?float $servingGrams = null,
        public ?string $ingredients = null,
        public array $allergens = [],
        public float $matchScore = 1.0,   // resolver confidence in the name match
    ) {}
}
