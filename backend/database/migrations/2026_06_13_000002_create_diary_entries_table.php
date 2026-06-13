<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('diary_entries', function (Blueprint $table) {
            // Client-generated UUID as PK → idempotent sync, no duplicates.
            $table->uuid('id')->primary();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('date_key', 10);   // yyyy-MM-dd (local)
            $table->string('meal');           // breakfast | lunch | dinner | snack
            $table->string('food_name');
            $table->float('grams');

            // Nutrition snapshot (immutable history).
            $table->float('kcal');
            $table->float('protein_g');
            $table->float('carbs_g');
            $table->float('fat_g');
            $table->float('fiber_g')->default(0);
            $table->float('sugar_g')->default(0);
            $table->float('sodium_mg')->default(0);

            $table->string('source')->default('search'); // scan | search | quick
            $table->string('emoji')->default('🍽️');
            $table->string('portion_label')->nullable();
            $table->float('hydration_ml')->default(0);
            $table->timestamp('logged_at');
            $table->timestamps();
            $table->softDeletes();            // tombstones for delete-sync

            $table->index(['user_id', 'date_key']);
            $table->index(['user_id', 'updated_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('diary_entries');
    }
};
