<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('favorites', function (Blueprint $table) {
            // Client-generated UUID as PK → idempotent sync, no duplicates.
            $table->uuid('id')->primary();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();

            // Enough of the food snapshot to re-log it without a DB lookup.
            $table->string('food_name');
            $table->string('emoji')->default('🍽️');
            $table->float('default_grams')->default(100);
            $table->string('portion_label')->nullable();

            // Per-100g nutrition basis.
            $table->float('kcal');
            $table->float('protein_g');
            $table->float('carbs_g');
            $table->float('fat_g');
            $table->float('fiber_g')->default(0);
            $table->float('sugar_g')->default(0);
            $table->float('sodium_mg')->default(0);

            $table->float('hydration_factor')->nullable();
            $table->string('source')->default('search');
            $table->timestamps();
            $table->softDeletes();

            $table->index(['user_id', 'updated_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('favorites');
    }
};
