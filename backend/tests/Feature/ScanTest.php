<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class ScanTest extends TestCase
{
    use RefreshDatabase;

    private function fakeVision(array $items): void
    {
        config(['calorielens.gemini_key' => 'test-key', 'calorielens.app_token' => null]);
        $json = json_encode(['dish_name' => 'Nasi Lemak', 'overall_note' => 'note', 'items' => $items]);
        Http::fake(['*generativelanguage*' => Http::response([
            'candidates' => [['content' => ['parts' => [['text' => $json]]]]],
        ], 200)]);
    }

    public function test_analyze_returns_validated_items_with_reconciled_calories(): void
    {
        $this->fakeVision([[
            'label' => 'Coconut Rice', 'emoji' => '🍚',
            'grams' => 180, 'grams_low' => 150, 'grams_high' => 215,
            'confidence' => 0.9, 'reasoning' => 'used plate as ref', 'is_drink' => false,
            // kcal deliberately wrong; macros imply 4*3+4*26+9*6 = 170
            'per_100g' => ['kcal' => 8000, 'protein_g' => 3, 'carbs_g' => 26, 'fat_g' => 6],
        ]]);

        $res = $this->postJson('/api/v1/scans/analyze', [
            'image' => base64_encode('fakejpegbytes'), 'media_type' => 'image/jpeg',
        ])->assertOk();

        $res->assertJsonPath('dish_name', 'Nasi Lemak')
            ->assertJsonPath('items.0.label', 'Coconut Rice')
            ->assertJsonPath('items.0.is_drink', false);
        $this->assertEqualsWithDelta(170, $res->json('items.0.per_100g.kcal'), 1.0);
    }

    public function test_app_token_gate_blocks_when_configured(): void
    {
        config(['calorielens.app_token' => 'secret']);

        $this->postJson('/api/v1/scans/analyze', ['image' => base64_encode('x')])
            ->assertStatus(401);

        $this->fakeVision([]);
        config(['calorielens.app_token' => 'secret']); // fakeVision nulled it; restore
        $this->withHeader('X-App-Token', 'secret')
            ->postJson('/api/v1/scans/analyze', ['image' => base64_encode('x')])
            ->assertOk();
    }

    public function test_rejects_non_base64_image(): void
    {
        config(['calorielens.app_token' => null]);
        $this->postJson('/api/v1/scans/analyze', ['image' => '!!!not base64!!!'])
            ->assertStatus(422);
    }
}
