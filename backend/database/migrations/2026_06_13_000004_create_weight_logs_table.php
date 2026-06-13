<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('weight_logs', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->string('date_key', 10);
            $table->float('kg');
            $table->timestamps();

            $table->unique(['user_id', 'date_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('weight_logs');
    }
};
