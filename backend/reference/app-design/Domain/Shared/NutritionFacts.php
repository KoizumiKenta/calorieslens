<?php

declare(strict_types=1);

namespace App\Domain\Shared;

/**
 * Immutable nutrition value object. All values absolute for the portion
 * they describe (use perHundredGrams()/scaledTo() to convert).
 */
final readonly class NutritionFacts
{
    public function __construct(
        public float $kcal,
        public float $proteinG = 0.0,
        public float $carbsG = 0.0,
        public float $fatG = 0.0,
        public ?float $fiberG = null,
        public ?float $sugarG = null,
        public ?float $sodiumMg = null,
    ) {}

    public static function zero(): self
    {
        return new self(0.0);
    }

    public function add(self $other): self
    {
        return new self(
            kcal: $this->kcal + $other->kcal,
            proteinG: $this->proteinG + $other->proteinG,
            carbsG: $this->carbsG + $other->carbsG,
            fatG: $this->fatG + $other->fatG,
            fiberG: self::addNullable($this->fiberG, $other->fiberG),
            sugarG: self::addNullable($this->sugarG, $other->sugarG),
            sodiumMg: self::addNullable($this->sodiumMg, $other->sodiumMg),
        );
    }

    /** Scale facts expressed per 100 g to an arbitrary gram amount. */
    public function scaledFromPer100g(float $grams): self
    {
        $f = $grams / 100.0;

        return new self(
            kcal: round($this->kcal * $f, 1),
            proteinG: round($this->proteinG * $f, 2),
            carbsG: round($this->carbsG * $f, 2),
            fatG: round($this->fatG * $f, 2),
            fiberG: $this->fiberG === null ? null : round($this->fiberG * $f, 2),
            sugarG: $this->sugarG === null ? null : round($this->sugarG * $f, 2),
            sodiumMg: $this->sodiumMg === null ? null : round($this->sodiumMg * $f, 1),
        );
    }

    /**
     * Atwater plausibility: kcal should roughly equal 4P + 4C + 9F.
     * Used by the nutrition validator to reject corrupt source data.
     */
    public function isCalorieConsistent(float $tolerance = 0.15): bool
    {
        $computed = 4 * $this->proteinG + 4 * $this->carbsG + 9 * $this->fatG;

        if ($computed < 1.0) {
            return $this->kcal < 25.0; // water, black coffee, etc.
        }

        return abs($this->kcal - $computed) / max($this->kcal, $computed) <= $tolerance;
    }

    public function toArray(): array
    {
        return array_filter([
            'kcal' => $this->kcal,
            'protein_g' => $this->proteinG,
            'carbs_g' => $this->carbsG,
            'fat_g' => $this->fatG,
            'fiber_g' => $this->fiberG,
            'sugar_g' => $this->sugarG,
            'sodium_mg' => $this->sodiumMg,
        ], static fn ($v) => $v !== null);
    }

    private static function addNullable(?float $a, ?float $b): ?float
    {
        return ($a === null && $b === null) ? null : ($a ?? 0.0) + ($b ?? 0.0);
    }
}
