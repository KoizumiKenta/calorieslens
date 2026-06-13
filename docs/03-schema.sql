-- CalorieLens AI — PostgreSQL 16 schema
-- Conventions: uuidv7 PKs, timestamptz, snake_case. Extensions first.

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;        -- pgvector for RAG
CREATE EXTENSION IF NOT EXISTS pg_uuidv7;

-- ============================================================ IDENTITY

CREATE TABLE users (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    email           citext UNIQUE NOT NULL,
    password_hash   text,                          -- null for social-only accounts
    auth_provider   text NOT NULL DEFAULT 'email', -- email|apple|google
    auth_provider_id text,
    email_verified_at timestamptz,
    locale          text NOT NULL DEFAULT 'en',
    timezone        text NOT NULL DEFAULT 'Asia/Kuala_Lumpur',
    keep_photos     boolean NOT NULL DEFAULT false,   -- privacy: retain scan originals
    status          text NOT NULL DEFAULT 'active',   -- active|suspended|deleted
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    deleted_at      timestamptz
);

CREATE TABLE user_profiles (
    user_id         uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    display_name    text NOT NULL,
    avatar_key      text,
    birth_date      date,
    sex             text,                            -- male|female|other|undisclosed
    height_cm       numeric(5,1),
    current_weight_kg numeric(5,2),
    goal_weight_kg  numeric(5,2),
    activity_level  text NOT NULL DEFAULT 'light',   -- sedentary|light|moderate|active|athlete
    fitness_goal    text NOT NULL DEFAULT 'maintain',-- lose|maintain|gain|recomp
    weekly_rate_kg  numeric(3,2) DEFAULT 0.5,        -- clamped server-side to safe band
    diet_prefs      text[] NOT NULL DEFAULT '{}',    -- vegan|vegetarian|halal|keto|paleo|gluten_free|low_carb
    allergies       text[] NOT NULL DEFAULT '{}',
    kcal_target     integer,                          -- computed; user-overridable
    protein_target_g integer,
    carbs_target_g  integer,
    fat_target_g    integer,
    water_target_ml integer NOT NULL DEFAULT 2000,
    updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE devices (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    platform        text NOT NULL,                   -- ios|android
    push_token      text,
    app_version     text,
    has_depth_sensor boolean DEFAULT false,
    last_seen_at    timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON devices (user_id);

CREATE TABLE refresh_tokens (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    token_hash  text NOT NULL UNIQUE,                -- sha256; raw never stored
    device_id   uuid REFERENCES devices(id) ON DELETE SET NULL,
    family_id   uuid NOT NULL,                       -- rotation family for reuse detection
    expires_at  timestamptz NOT NULL,
    revoked_at  timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON refresh_tokens (user_id, family_id);

-- ============================================================ FOOD GRAPH

CREATE TABLE food_categories (
    id        smallint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    slug      text UNIQUE NOT NULL,
    name      text NOT NULL,
    parent_id smallint REFERENCES food_categories(id)
);

CREATE TABLE food_items (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    canonical_name  text NOT NULL,
    category_id     smallint REFERENCES food_categories(id),
    is_composite    boolean NOT NULL DEFAULT false,
    is_beverage     boolean NOT NULL DEFAULT false,
    density_g_ml    numeric(5,3),                    -- volume→weight conversion
    source          text NOT NULL DEFAULT 'curated', -- curated|usda|off|nutritionix|edamam|spoonacular|community|user
    source_ref      text,
    verification    text NOT NULL DEFAULT 'unverified', -- verified|community|unverified
    locale_origin   text,                            -- MY|SG|ID|TH|CN|JP|KR|IN|...
    diet_flags      text[] NOT NULL DEFAULT '{}',    -- halal, vegan, vegetarian, gluten_free...
    allergens       text[] NOT NULL DEFAULT '{}',
    popularity      integer NOT NULL DEFAULT 0,
    created_by      uuid REFERENCES users(id),       -- for user/community foods
    visibility      text NOT NULL DEFAULT 'global',  -- global|private
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    deleted_at      timestamptz
);
CREATE INDEX food_items_name_trgm ON food_items USING gin (canonical_name gin_trgm_ops);
CREATE INDEX ON food_items (verification, locale_origin);

CREATE TABLE food_nutrients_core (        -- per 100 g (or 100 ml for beverages)
    food_item_id uuid PRIMARY KEY REFERENCES food_items(id) ON DELETE CASCADE,
    kcal        numeric(7,1) NOT NULL,
    protein_g   numeric(6,2) NOT NULL DEFAULT 0,
    carbs_g     numeric(6,2) NOT NULL DEFAULT 0,
    fat_g       numeric(6,2) NOT NULL DEFAULT 0,
    fiber_g     numeric(6,2),
    sugar_g     numeric(6,2),
    sodium_mg   numeric(8,1),
    sat_fat_g   numeric(6,2),
    cholesterol_mg numeric(7,1)
);

CREATE TABLE food_nutrients_extended (    -- long tail: vitamins, minerals, aminos
    food_item_id uuid PRIMARY KEY REFERENCES food_items(id) ON DELETE CASCADE,
    nutrients    jsonb NOT NULL DEFAULT '{}'   -- {"vit_c_mg": 12.4, "iron_mg": 1.1, ...}
);

CREATE TABLE food_portions (              -- household measures
    id           uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    food_item_id uuid NOT NULL REFERENCES food_items(id) ON DELETE CASCADE,
    label        text NOT NULL,            -- "1 bowl", "1 medium", "1 slice", "1 cup cooked"
    grams        numeric(7,1) NOT NULL,
    is_default   boolean NOT NULL DEFAULT false
);
CREATE INDEX ON food_portions (food_item_id);

CREATE TABLE food_translations (
    food_item_id uuid NOT NULL REFERENCES food_items(id) ON DELETE CASCADE,
    locale       text NOT NULL,            -- ms|zh|id|th|...
    name         text NOT NULL,
    aliases      text[] NOT NULL DEFAULT '{}',
    PRIMARY KEY (food_item_id, locale)
);
CREATE INDEX food_translations_trgm ON food_translations USING gin (name gin_trgm_ops);

CREATE TABLE composite_components (       -- mixed-dish decomposition templates
    parent_food_id    uuid NOT NULL REFERENCES food_items(id) ON DELETE CASCADE,
    component_food_id uuid NOT NULL REFERENCES food_items(id),
    typical_grams     numeric(7,1) NOT NULL,
    ratio             numeric(4,3) NOT NULL,   -- share of dish weight
    optional          boolean NOT NULL DEFAULT false,
    PRIMARY KEY (parent_food_id, component_food_id)
);

CREATE TABLE cooking_modifiers (          -- grilled vs fried multipliers
    id           smallint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    method       text UNIQUE NOT NULL,     -- raw|boiled|steamed|grilled|baked|stir_fried|deep_fried
    kcal_mult    numeric(4,3) NOT NULL DEFAULT 1.0,
    fat_add_g_per_100g numeric(5,2) NOT NULL DEFAULT 0,
    sodium_add_mg_per_100g numeric(7,1) NOT NULL DEFAULT 0
);

CREATE TABLE barcode_products (
    id            uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    barcode       text UNIQUE NOT NULL,    -- EAN-13/UPC-A normalized
    food_item_id  uuid REFERENCES food_items(id),
    brand         text,
    product_name  text NOT NULL,
    package_size  text,
    serving_grams numeric(7,1),
    ingredients   text,
    source        text NOT NULL DEFAULT 'off',
    verification  text NOT NULL DEFAULT 'unverified',
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE food_revisions (             -- versioned nutrition edits (admin audit/rollback)
    id           uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    food_item_id uuid NOT NULL REFERENCES food_items(id) ON DELETE CASCADE,
    edited_by    uuid REFERENCES users(id),
    before       jsonb NOT NULL,
    after        jsonb NOT NULL,
    reason       text,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE food_submissions (           -- community queue (unknown barcodes, new foods)
    id            uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id       uuid NOT NULL REFERENCES users(id),
    kind          text NOT NULL,           -- barcode|food|correction
    barcode       text,
    payload       jsonb NOT NULL,          -- proposed fields incl. OCR extraction
    media_keys    text[] NOT NULL DEFAULT '{}',
    status        text NOT NULL DEFAULT 'pending', -- pending|approved|rejected|merged
    reviewed_by   uuid REFERENCES users(id),
    reviewed_at   timestamptz,
    review_note   text,
    created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON food_submissions (status, created_at);

-- ============================================================ SCANS & AI

CREATE TABLE media_objects (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    storage_key text NOT NULL,
    kind        text NOT NULL,             -- meal_photo|label|barcode_frame|receipt|menu|pantry|avatar
    mime        text NOT NULL,
    bytes       integer NOT NULL,
    width       integer, height integer,
    phash       text,                      -- perceptual hash for dedupe
    purge_after timestamptz,               -- privacy auto-deletion
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON media_objects (purge_after) WHERE purge_after IS NOT NULL;

CREATE TABLE meal_scans (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind        text NOT NULL,             -- photo|multi_angle|video|barcode|label_ocr|voice|receipt|menu|pantry|before_after
    status      text NOT NULL DEFAULT 'pending', -- pending|uploading|processing|ready|failed|expired
    media_ids   uuid[] NOT NULL DEFAULT '{}',
    depth_map_key text,
    parent_scan_id uuid REFERENCES meal_scans(id),  -- after-photo links to before-scan
    meta        jsonb NOT NULL DEFAULT '{}',        -- angle labels, locale hints, mealtime
    error_code  text,
    created_at  timestamptz NOT NULL DEFAULT now(),
    completed_at timestamptz
) PARTITION BY RANGE (created_at);
CREATE INDEX ON meal_scans (user_id, created_at DESC);

CREATE TABLE scan_results (
    id            uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    scan_id       uuid NOT NULL,           -- FK enforced app-side (partitioned parent)
    provider      text NOT NULL,           -- openai|gemini|claude
    model         text NOT NULL,
    total_kcal    numeric(7,1),
    kcal_low      numeric(7,1),
    kcal_high     numeric(7,1),
    confidence    numeric(4,3),
    reasoning     text,                    -- meal-level explanation
    raw_response  jsonb,                   -- retained 7 d for debugging, then nulled
    latency_ms    integer,
    cost_usd      numeric(8,5),
    created_at    timestamptz NOT NULL DEFAULT now()
) PARTITION BY RANGE (created_at);

CREATE TABLE scan_result_items (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    scan_result_id  uuid NOT NULL,
    food_item_id    uuid REFERENCES food_items(id),
    detected_label  text NOT NULL,
    component_of    uuid,                  -- self-ref: composite parent item
    grams           numeric(7,1) NOT NULL,
    grams_low       numeric(7,1),
    grams_high      numeric(7,1),
    serving_label   text,                  -- "1 bowl", "2 slices"
    cooking_method  text,
    kcal            numeric(7,1) NOT NULL,
    protein_g       numeric(6,2), carbs_g numeric(6,2), fat_g numeric(6,2),
    fiber_g         numeric(6,2), sugar_g numeric(6,2), sodium_mg numeric(8,1),
    confidence      numeric(4,3) NOT NULL,
    portion_confidence numeric(4,3),
    reasoning       text,                  -- per-item explanation
    bbox            jsonb,                 -- normalized [x,y,w,h] for overlay UI
    consumed_fraction numeric(4,3)         -- set by before/after flow
);
CREATE INDEX ON scan_result_items (scan_result_id);

CREATE TABLE user_food_priors (           -- personalization learned from corrections
    id           uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind         text NOT NULL,            -- portion_bias|label_remap|usual_meal
    match_key    text NOT NULL,            -- food_item_id, detected label, or scan fingerprint
    payload      jsonb NOT NULL,           -- {avg_ratio: 0.82, n: 5} | {remap_to: uuid} | {items: [...]}
    strength     numeric(4,3) NOT NULL DEFAULT 0.5,
    updated_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, kind, match_key)
);

CREATE TABLE ai_usage_events (            -- metering & cost analytics
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id     uuid,
    capability  text NOT NULL,             -- vision|ocr|stt|chat|embedding
    provider    text NOT NULL,
    model       text NOT NULL,
    tokens_in   integer, tokens_out integer,
    cost_usd    numeric(8,5),
    latency_ms  integer,
    success     boolean NOT NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
) PARTITION BY RANGE (created_at);

-- ============================================================ DIARY & TRACKING

CREATE TABLE diary_entries (
    id            uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    client_uuid   uuid NOT NULL,           -- offline idempotency
    entry_date    date NOT NULL,           -- user-local date
    entry_tz      text NOT NULL,
    meal_slot     text NOT NULL,           -- breakfast|lunch|dinner|snack
    food_item_id  uuid REFERENCES food_items(id),
    scan_result_item_id uuid,
    display_name  text NOT NULL,           -- snapshot
    grams         numeric(7,1),
    serving_label text,
    quantity      numeric(6,2) NOT NULL DEFAULT 1,
    kcal          numeric(7,1) NOT NULL,   -- snapshots: immutable history
    protein_g     numeric(6,2) NOT NULL DEFAULT 0,
    carbs_g       numeric(6,2) NOT NULL DEFAULT 0,
    fat_g         numeric(6,2) NOT NULL DEFAULT 0,
    fiber_g       numeric(6,2), sugar_g numeric(6,2), sodium_mg numeric(8,1),
    source        text NOT NULL DEFAULT 'manual', -- manual|photo|barcode|label|voice|favorite|template|receipt|coach
    logged_at     timestamptz NOT NULL DEFAULT now(),
    deleted_at    timestamptz,
    UNIQUE (user_id, client_uuid)
) PARTITION BY RANGE (logged_at);
CREATE INDEX ON diary_entries (user_id, entry_date);

CREATE TABLE weight_logs (
    id        uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id   uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    weight_kg numeric(5,2) NOT NULL,
    logged_on date NOT NULL,
    source    text NOT NULL DEFAULT 'manual', -- manual|healthkit|health_connect|garmin|fitbit
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, logged_on, source)
);

CREATE TABLE water_logs (
    id        uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id   uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    ml        integer NOT NULL,
    entry_date date NOT NULL,
    logged_at timestamptz NOT NULL DEFAULT now()
) PARTITION BY RANGE (logged_at);

CREATE TABLE exercise_logs (
    id           uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    activity     text NOT NULL,            -- walking|running|cycling|swimming|weights|hiit|yoga|other
    duration_min integer NOT NULL,
    kcal_burned  numeric(7,1) NOT NULL,
    entry_date   date NOT NULL,
    source       text NOT NULL DEFAULT 'manual',
    external_id  text,                     -- wearable workout id (dedupe)
    logged_at    timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, source, external_id)
) PARTITION BY RANGE (logged_at);

CREATE TABLE health_sync_batches (        -- wearable import idempotency
    id           uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    provider     text NOT NULL,
    metric       text NOT NULL,            -- steps|active_kcal|heart_rate|sleep|workout
    period_start timestamptz NOT NULL,
    period_end   timestamptz NOT NULL,
    payload      jsonb NOT NULL,
    created_at   timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, provider, metric, period_start, period_end)
);

CREATE TABLE favorites (
    id           uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    label        text NOT NULL,
    snapshot     jsonb NOT NULL,            -- full nutrition payload for one-tap log
    use_count    integer NOT NULL DEFAULT 0,
    created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE meal_templates (
    id        uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id   uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name      text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE meal_template_items (
    id           uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    template_id  uuid NOT NULL REFERENCES meal_templates(id) ON DELETE CASCADE,
    food_item_id uuid REFERENCES food_items(id),
    display_name text NOT NULL,
    grams        numeric(7,1),
    quantity     numeric(6,2) NOT NULL DEFAULT 1,
    snapshot     jsonb NOT NULL
);

CREATE TABLE meal_plans (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    week_start  date NOT NULL,
    constraints jsonb NOT NULL,             -- budget, cuisines, cook_time, protein, restrictions
    plan        jsonb NOT NULL,             -- 7 days × meals with food refs + nutrition
    grocery_list jsonb,
    created_at  timestamptz NOT NULL DEFAULT now()
);

-- ============================================================ COACH & RAG

CREATE TABLE chat_conversations (
    id         uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title      text,
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE chat_messages (
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    conversation_id uuid NOT NULL REFERENCES chat_conversations(id) ON DELETE CASCADE,
    role            text NOT NULL,          -- user|assistant|tool
    content         text NOT NULL,
    grounding       jsonb,                  -- retrieved chunks + diary refs used
    created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON chat_messages (conversation_id, created_at);

CREATE TABLE knowledge_documents (
    id         uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    title      text NOT NULL,
    source_url text,
    authority  smallint NOT NULL DEFAULT 3, -- 1 low … 5 clinical guideline
    locale     text NOT NULL DEFAULT 'en',
    created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE knowledge_chunks (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    document_id uuid NOT NULL REFERENCES knowledge_documents(id) ON DELETE CASCADE,
    content     text NOT NULL,
    embedding   vector(1536) NOT NULL,
    meta        jsonb NOT NULL DEFAULT '{}'
);
CREATE INDEX ON knowledge_chunks USING hnsw (embedding vector_cosine_ops);

CREATE TABLE daily_insights (
    id         uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    insight_date date NOT NULL,
    kind       text NOT NULL,               -- low_protein|high_sodium|skipped_meal|pattern|hydration
    message    text NOT NULL,
    cta        jsonb,
    dismissed  boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE (user_id, insight_date, kind)
);

-- ============================================================ GAMIFICATION & SOCIAL

CREATE TABLE user_stats (
    user_id        uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    xp             integer NOT NULL DEFAULT 0,
    level          integer NOT NULL DEFAULT 1,
    current_streak integer NOT NULL DEFAULT 0,
    longest_streak integer NOT NULL DEFAULT 0,
    last_log_date  date,
    streak_freezes integer NOT NULL DEFAULT 1,
    updated_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE achievements (
    id        smallint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    slug      text UNIQUE NOT NULL,         -- streak_7, protein_week, first_scan, weight_milestone_5
    name      text NOT NULL,
    description text NOT NULL,
    xp_reward integer NOT NULL DEFAULT 50
);
CREATE TABLE user_achievements (
    user_id        uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    achievement_id smallint NOT NULL REFERENCES achievements(id),
    earned_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, achievement_id)
);

CREATE TABLE follows (
    follower_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    followee_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at  timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (follower_id, followee_id)
);

CREATE TABLE shared_meals (
    id         uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    diary_entry_ids uuid[] NOT NULL,
    caption    text,
    media_key  text,
    visibility text NOT NULL DEFAULT 'followers', -- followers|group|public
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE challenges (
    id         uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    slug       text UNIQUE NOT NULL,
    name       text NOT NULL,
    kind       text NOT NULL,               -- protein|water|streak|steps|custom
    target     jsonb NOT NULL,
    starts_on  date NOT NULL,
    ends_on    date NOT NULL
);
CREATE TABLE challenge_participants (
    challenge_id uuid NOT NULL REFERENCES challenges(id) ON DELETE CASCADE,
    user_id      uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    progress     jsonb NOT NULL DEFAULT '{}',
    joined_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (challenge_id, user_id)
);

-- ============================================================ PLATFORM

CREATE TABLE subscriptions (
    user_id      uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    tier         text NOT NULL DEFAULT 'free',  -- free|premium|family|enterprise
    store        text,                           -- app_store|play|stripe
    external_ref text,
    renews_at    timestamptz,
    expires_at   timestamptz,
    family_owner uuid REFERENCES users(id),
    updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE subscription_events (
    id         uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id    uuid NOT NULL,
    event      text NOT NULL,                -- purchased|renewed|cancelled|refunded|grace
    payload    jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE admin_roles (
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role    text NOT NULL,                   -- super_admin|moderator|nutritionist|analyst|support
    PRIMARY KEY (user_id, role)
);

CREATE TABLE audit_logs (
    id         uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    actor_id   uuid,
    actor_type text NOT NULL DEFAULT 'user', -- user|admin|system
    action     text NOT NULL,                -- food.updated, user.suspended, submission.approved...
    subject_type text, subject_id text,
    ip         inet,
    changes    jsonb,
    created_at timestamptz NOT NULL DEFAULT now()
) PARTITION BY RANGE (created_at);

CREATE TABLE notification_prefs (
    user_id        uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    insights       boolean NOT NULL DEFAULT true,
    water_reminders boolean NOT NULL DEFAULT true,
    streak_alerts  boolean NOT NULL DEFAULT true,
    social         boolean NOT NULL DEFAULT true,
    quiet_start    time NOT NULL DEFAULT '22:00',
    quiet_end      time NOT NULL DEFAULT '08:00'
);

-- Partition bootstrap (managed by scheduled job creating next-month partitions)
-- Example:
CREATE TABLE diary_entries_2026_06 PARTITION OF diary_entries
    FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
