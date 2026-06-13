<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('foods', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('source');                 // curated | off | ai
            $table->string('external_id')->nullable(); // e.g. OFF barcode
            $table->string('name');
            $table->string('brand')->nullable();
            $table->string('region', 8)->nullable();   // MY | SG | ID | TH
            $table->string('emoji', 16)->default('🍽️');

            // Per-100g basis (the canonical nutrition shape).
            $table->float('kcal');
            $table->float('protein_g')->default(0);
            $table->float('carbs_g')->default(0);
            $table->float('fat_g')->default(0);
            $table->float('fiber_g')->default(0);
            $table->float('sugar_g')->default(0);
            $table->float('sodium_mg')->default(0);

            $table->json('portions')->nullable();      // [{label, grams}]
            $table->json('aliases')->nullable();       // ["kuey teow", ...]
            $table->float('hydration_factor')->nullable();
            $table->boolean('verified')->default(false); // curated/trusted
            $table->unsignedInteger('popularity')->default(0); // log frequency

            $table->timestamps();

            $table->unique(['source', 'external_id']);
            $table->index('name');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('foods');
    }
};
