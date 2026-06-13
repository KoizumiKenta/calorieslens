<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SyncFlowTest extends TestCase
{
    use RefreshDatabase;

    public function test_register_returns_a_token(): void
    {
        $res = $this->postJson('/api/v1/auth/register', [
            'name' => 'Kent',
            'email' => 'kent@example.com',
            'password' => 'secret123',
        ]);

        $res->assertCreated()->assertJsonStructure(['token', 'user' => ['id', 'name', 'email']]);
    }

    public function test_login_rejects_wrong_password(): void
    {
        User::factory()->create(['email' => 'a@b.com', 'password' => 'secret123']);

        $this->postJson('/api/v1/auth/login', ['email' => 'a@b.com', 'password' => 'nope'])
            ->assertStatus(422);
    }

    public function test_protected_routes_require_auth(): void
    {
        $this->getJson('/api/v1/sync')->assertUnauthorized();
    }

    public function test_profile_upserts_and_returns_via_me(): void
    {
        $user = User::factory()->create();

        $this->actingAs($user)->putJson('/api/v1/profile', [
            'name' => 'Kent', 'sex' => 'male', 'age' => 29,
            'height_cm' => 175, 'weight_kg' => 113.9,
            'activity' => 'light', 'goal' => 'lose',
        ])->assertOk();

        $this->actingAs($user)->getJson('/api/v1/me')
            ->assertOk()
            ->assertJsonPath('profile.weight_kg', 113.9)
            ->assertJsonPath('profile.goal', 'lose');

        $this->assertDatabaseCount('profiles', 1); // upsert, not duplicate
    }

    public function test_push_is_idempotent_and_preserves_fields(): void
    {
        $user = User::factory()->create();
        $entry = [
            'id' => '22222222-2222-4222-8222-222222222222',
            'date_key' => '2026-06-13', 'meal' => 'lunch', 'food_name' => 'Teh Tarik',
            'grams' => 250, 'nutrition' => ['kcal' => 162, 'protein_g' => 3.75, 'carbs_g' => 26.25, 'fat_g' => 4.5],
            'source' => 'search', 'emoji' => '🧋', 'portion_label' => '1 glass', 'hydration_ml' => 225,
        ];

        // Push the same entry twice.
        $this->actingAs($user)->postJson('/api/v1/sync', ['diary_entries' => [$entry]])->assertOk();
        $this->actingAs($user)->postJson('/api/v1/sync', ['diary_entries' => [$entry]])->assertOk();

        $this->assertDatabaseCount('diary_entries', 1); // no duplicate

        $this->actingAs($user)->getJson('/api/v1/sync')
            ->assertOk()
            ->assertJsonPath('diary_entries.0.emoji', '🧋')
            ->assertJsonPath('diary_entries.0.portion_label', '1 glass')
            ->assertJsonPath('diary_entries.0.hydration_ml', 225)
            ->assertJsonPath('diary_entries.0.deleted', false);
    }

    public function test_delete_propagates_as_tombstone(): void
    {
        $user = User::factory()->create();
        $id = '33333333-3333-4333-8333-333333333333';
        $this->actingAs($user)->postJson('/api/v1/sync', ['diary_entries' => [[
            'id' => $id, 'date_key' => '2026-06-13', 'meal' => 'dinner', 'food_name' => 'Roti Canai',
            'grams' => 100, 'nutrition' => ['kcal' => 300, 'protein_g' => 6.5, 'carbs_g' => 42, 'fat_g' => 11.5],
        ]]])->assertOk();

        $this->actingAs($user)->postJson('/api/v1/sync', ['deleted_ids' => [$id]])->assertOk();

        $this->actingAs($user)->getJson('/api/v1/sync')
            ->assertOk()
            ->assertJsonPath('diary_entries.0.deleted', true);
    }

    public function test_users_cannot_see_each_others_data(): void
    {
        $alice = User::factory()->create();
        $bob = User::factory()->create();

        $this->actingAs($alice)->postJson('/api/v1/sync', ['weights' => [['date_key' => '2026-06-13', 'kg' => 70]]]);

        $this->actingAs($bob)->getJson('/api/v1/sync')
            ->assertOk()
            ->assertJsonCount(0, 'weights');
    }
}
