<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('profiles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->unique()->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->string('sex');            // male | female
            $table->unsignedSmallInteger('age');
            $table->float('height_cm');
            $table->float('weight_kg');
            $table->string('activity');       // sedentary | light | moderate | active | veryActive
            $table->string('goal');           // lose | maintain | gain
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('profiles');
    }
};
