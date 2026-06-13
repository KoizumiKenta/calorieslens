<?php

namespace Tests\Feature;

use App\Models\Food;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class FoodSearchTest extends TestCase
{
    use RefreshDatabase;

    private function curated(array $attrs = []): Food
    {
        return Food::create(array_merge([
            'source' => 'curated', 'external_id' => 'my-char-kway-teow',
            'name' => 'Char Kway Teow', 'aliases' => ['kuey teow', 'ckt'],
            'region' => 'MY', 'emoji' => '🍜', 'kcal' => 185,
            'protein_g' => 6.5, 'carbs_g' => 20, 'fat_g' => 8.8,
            'verified' => true, 'popularity' => 100,
        ], $attrs));
    }

    public function test_short_queries_return_nothing(): void
    {
        Http::fake();
        $this->getJson('/api/v1/foods/search?q=a')
            ->assertOk()
            ->assertJsonCount(0, 'results');
    }

    public function test_curated_alias_matches_and_ranks_first(): void
    {
        $this->curated();
        Http::fake(['*openfoodfacts*' => Http::response(['products' => []], 200)]);

        $this->getJson('/api/v1/foods/search?q=kuey teow')
            ->assertOk()
            ->assertJsonPath('results.0.name', 'Char Kway Teow')
            ->assertJsonPath('results.0.source', 'curated');
    }

    public function test_off_results_merge_and_calories_are_reconciled(): void
    {
        $this->curated(); // 1 local hit (<8) → OFF is consulted
        Http::fake(['*openfoodfacts*' => Http::response([
            'products' => [[
                'code' => '12345',
                'product_name' => 'Grilled Chicken Fillet',
                'brands' => 'Acme',
                'serving_size' => '120 g',
                // kcal grossly wrong (kJ mislabeled); macros imply ~156.
                'nutriments' => [
                    'energy-kcal_100g' => 9999,
                    'proteins_100g' => 31, 'carbohydrates_100g' => 0, 'fat_100g' => 3.6,
                    'sodium_100g' => 0.4,
                ],
            ]],
        ], 200)]);

        $res = $this->getJson('/api/v1/foods/search?q=chicken')->assertOk();

        $off = collect($res->json('results'))->firstWhere('source', 'off');
        $this->assertNotNull($off, 'OFF result should be merged in');
        $this->assertEqualsWithDelta(156.4, $off['per_100g']['kcal'], 1.0); // Atwater repaired
        $this->assertEquals(400, $off['per_100g']['sodium_mg']);            // g→mg
        $this->assertEquals(120, $off['portions'][0]['grams']);            // serving parsed

        // And it was cached for next time.
        $this->assertDatabaseHas('foods', ['source' => 'off', 'external_id' => '12345']);
    }

    public function test_falls_back_gracefully_when_off_errors(): void
    {
        $this->curated();
        Http::fake(['*openfoodfacts*' => Http::response('boom', 500)]);

        $this->getJson('/api/v1/foods/search?q=kuey teow')
            ->assertOk()
            ->assertJsonPath('results.0.name', 'Char Kway Teow');
    }

    public function test_ai_estimate_creates_caches_and_reconciles(): void
    {
        config(['calorielens.gemini_key' => 'test-key']); // satisfies guard; call is faked

        $modelJson = json_encode([
            'name' => 'Ban Mee', 'emoji' => '🍜', 'region' => 'MY', 'is_drink' => false,
            'per_100g' => [
                // kcal wrong on purpose; macros imply 4*10+4*15+9*5 = 145
                'kcal' => 5000, 'protein_g' => 10, 'carbs_g' => 15, 'fat_g' => 5, 'sodium_mg' => 600,
            ],
            'portions' => [['label' => '1 bowl', 'grams' => 450]],
            'aliases' => ['pan mee'],
        ]);
        Http::fake(['*generativelanguage*' => Http::response([
            'candidates' => [['content' => ['parts' => [['text' => $modelJson]]]]],
        ], 200)]);

        $res = $this->postJson('/api/v1/foods/estimate', ['name' => 'ban mee'])->assertOk();
        $res->assertJsonPath('cached', false)
            ->assertJsonPath('food.name', 'Ban Mee')
            ->assertJsonPath('food.region', 'MY');
        $this->assertEqualsWithDelta(145, $res->json('food.per_100g.kcal'), 1.0); // Atwater repaired

        $this->assertDatabaseHas('foods', ['source' => 'ai', 'external_id' => 'ban-mee']);

        // Second call is served from cache — no extra provider request.
        $this->postJson('/api/v1/foods/estimate', ['name' => 'Ban Mee'])
            ->assertOk()->assertJsonPath('cached', true);
        Http::assertSentCount(1);
    }
}
