<?php

namespace App\Support;

/**
 * Calorie sanity check (docs §NutritionValidator). Real-world food data —
 * especially crowd-sourced — often has kcal that disagree with the macros
 * (kJ mislabeled as kcal, per-serving vs per-100g mixups). Atwater: a gram of
 * protein/carb ≈ 4 kcal, fat ≈ 9. If the stated kcal is wildly off the macro
 * math, trust the macros instead.
 */
class Atwater
{
    public static function kcalFromMacros(float $protein, float $carbs, float $fat): float
    {
        return 4 * $protein + 4 * $carbs + 9 * $fat;
    }

    /** Returns a kcal value reconciled with the macros (repairs gross errors). */
    public static function reconcile(float $kcal, float $protein, float $carbs, float $fat): float
    {
        $expected = self::kcalFromMacros($protein, $carbs, $fat);
        if ($expected <= 0) {
            return max(0, $kcal);
        }
        if ($kcal <= 0) {
            return $expected;
        }
        $drift = abs($kcal - $expected) / $expected;
        return $drift > 0.30 ? $expected : $kcal;
    }

    /** A row is usable if it has calories and at least one macro. */
    public static function isPlausible(float $kcal, float $protein, float $carbs, float $fat): bool
    {
        return $kcal > 0 && ($protein + $carbs + $fat) > 0 && $kcal < 950; // >900/100g is implausible (pure fat = 900)
    }
}
