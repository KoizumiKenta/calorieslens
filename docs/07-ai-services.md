# CalorieLens AI — AI Service Architecture

All AI capabilities sit behind capability interfaces in `backend/app/Domain/AI/`. Business logic depends only on contracts; providers are config-selected with health-checked fallback chains and circuit breakers. Implemented code: see `backend/app/Domain/AI/` and `backend/config/ai.php`.

## 1. Capability contracts

| Contract | Capability | Providers (priority order) |
|---|---|---|
| `VisionProviderContract` | Food detection, segmentation, portion & nutrition estimation, reference-object detection, before/after diff, pantry/menu/receipt understanding | Gemini Vision → OpenAI Vision → Claude Vision |
| `OcrProviderContract` | Nutrition label & receipt text extraction | Google Cloud Vision → AWS Textract → Tesseract (self-hosted, last resort) |
| `SpeechProviderContract` | Voice log transcription | Whisper API → Google STT |
| `LlmProviderContract` | Coach chat, voice-log structuring, meal planning, insight phrasing | Claude → GPT → Gemini |
| `EmbeddingProviderContract` | RAG retrieval, food-name semantic matching | text-embedding-3-small (1536-d) |

Provider order per capability is intentional: vision priority is benchmarked on the internal food eval set per release, not vendor loyalty; LLM coach prioritizes safety/instructability. **Order is config, never code** (`config/ai.php`), so price/quality arbitrage requires no deploy.

### Resilience wrapper (every provider call)

```
AIManager::vision()->analyze(...)            // call site
  └─ FallbackChain                            // tries providers in configured order
       └─ CircuitBreaker (per provider)       // open after 5 failures/60 s, half-open probe
            └─ RetryPolicy (2 retries, jittered backoff, idempotent ops only)
                 └─ Timeout (capability-specific: vision 20 s, chat first-token 4 s)
                      └─ Provider adapter     // normalizes request/response/errors
  side effects: ai_usage_events row (tokens, cost, latency), Prometheus metrics,
                ProviderDegraded event when breaker opens
```

## 2. Vision pipeline — structured output, not prose

Every vision provider is prompted with the same canonical instruction set + a strict JSON schema (provider-native structured output where supported, schema-validated and one-shot-repaired otherwise):

```jsonc
{
  "items": [{
    "label": "chicken breast",
    "category_hint": "protein|grain|vegetable|fruit|dairy|beverage|dessert|mixed_dish",
    "is_composite": false,
    "components": [],                  // filled for mixed dishes
    "cooking_method": "grilled",
    "portion": {"grams": 150, "low": 130, "high": 175, "serving_label": "1 piece",
                 "basis": "plate_fraction|reference_object|depth|count"},
    "bbox": [0.12, 0.30, 0.35, 0.40],
    "confidence": 0.96,
    "reasoning": "Char lines and fiber texture indicate grilled chicken breast; width ≈ 1.6× fork head."
  }],
  "reference_objects": [{"type": "fork", "bbox": [...], "est_px_per_mm": 4.1}],
  "plate": {"detected": true, "diameter_cm_est": 26},
  "image_quality": {"blur": 0.1, "lighting": "good", "occlusion": 0.05},
  "meal_reasoning": "Standard protein-rice-vegetable plate, restaurant portioning."
}
```

Key rules baked into the system prompt:
- Never guess hidden foods; flag occlusion instead.
- Mixed/regional dishes → decompose (`components`) using the dish vocabulary list injected for the user's locale (e.g., MY list includes nasi lemak, mee goreng, roti canai, laksa, chendol…).
- Portion `basis` must be declared — this drives how downstream fusion weighs the estimate.
- Confidence is calibrated by post-hoc calibration table (Platt-style mapping learned from correction data, applied server-side) — raw model confidence is never shown to users.

### Portion fusion (stage 4 of the pipeline)

`PortionEstimator` combines independent signals into grams + variance:

| Signal | Weight | Source |
|---|---|---|
| Vision plate-fraction estimate | base | provider output |
| Reference-object scale | ×1.5 when px/mm known | utensil/card/coin detection |
| Depth-map volume × density | ×2.0 when available | device LiDAR/ToF upload, `food_items.density_g_ml` |
| Multi-angle/video agreement | trimmed mean across frames | fusion step |
| User portion prior | shifts mean by learned bias | `user_food_priors.portion_bias` |

Output = inverse-variance weighted mean; range = ±1.28σ (80% interval) shown as `grams_range`. Meal-level kcal range = root-sum-square of item variances (items aren't perfectly correlated; documented assumption).

### Before/after consumption

After-photo scan carries `parent_scan_id`. The provider receives both images plus the before-items list and returns per-item `remaining_fraction`. Consumed nutrition = before × (1 − remaining). UI shows "You ate ~70% of the rice" with override slider.

## 3. OCR pipeline (nutrition labels & receipts)

1. **Pre-process** (server, Imagick/libvips): deskew via Hough transform, perspective correction, adaptive contrast, glare masking.
2. **OCR provider** → raw text + word geometry.
3. **Label parser** (`LabelParser`): locale-aware unit/term dictionary (EN/MS/ZH/ID/TH: "Energy/Tenaga/能量", kJ↔kcal conversion, per-100g vs per-serving disambiguation by column geometry), regex+geometry extraction into the nutrition panel struct, ingredient block segmentation, allergen keyword tagging.
4. **LLM repair pass** (cheap model): only for fields the deterministic parser flagged ambiguous — never allowed to invent values; missing stays missing.
5. **Confidence per field** → UI pre-fills the custom-food form with low-confidence fields highlighted for review.

## 4. Voice logging

Audio (≤ 60 s, Opus) → STT → LLM structuring with tool-schema:
`[{food_query: "boiled eggs", quantity: 2, unit: "piece"}, {food_query: "protein shake", quantity: 1, unit: "serving"}]`
→ each `food_query` through the standard food resolver → confirmation sheet. Ambiguity ("a bowl of noodles") → resolver returns top-3, UI asks. Locale-mixed speech (Manglish/Singlish) handled by STT language hints from profile.

## 5. Nutrition data resolver

`NutritionResolver` (see `backend/app/Domain/Nutrition/`) resolves a label/query → canonical nutrition through a prioritized source chain:

```
1. Internal curated DB (verified rows)          — authoritative, regional
2. Redis cache of past external resolutions     — 30 d TTL
3. USDA FoodData Central                        — generic/raw foods
4. Open Food Facts                              — barcodes, global packaged
5. Nutritionix                                  — branded/restaurant (quota-metered)
6. Edamam                                       — recipes/generic fallback
7. Spoonacular                                  — recipes/menu items
```

Per-source adapters normalize to per-100 g; a **plausibility validator** rejects rows violating Atwater consistency (|kcal − (4P+4C+9F)| > 15%) or absurd densities before they enter cache/DB. External hits matching ≥ N user lookups are promoted into `food_items` (source-tagged, unverified) for the moderation pipeline. Every source call is metered for quota & cost dashboards.

## 6. RAG for the coach

- **Corpus:** curated, citation-carrying documents only — national dietary guidelines (MY MOH, SG HPB, WHO), macro/micronutrient references, sports-nutrition position stands, food-safety basics. No scraped blogs. ~2k documents → chunked (400 tokens, 15% overlap) → pgvector HNSW.
- **Retrieval:** query embedding → top-12 cosine → re-rank by authority × recency → top-4 into context.
- **Grounding contract in the system prompt:** the coach may only state user-specific numbers that appear in the injected diary context; nutrition science claims must trace to retrieved chunks; otherwise it must say it doesn't have the data. `chat_messages.grounding` stores what was injected (auditable).
- **Coach context builder:** compact daily summary (targets, consumed, macro gaps, last 7-day pattern, weight trend, prefs/allergies) — cached in Redis, invalidated on log events. Typically < 800 tokens.
- **Tool use:** the coach LLM gets tools — `get_diary(date_range)`, `search_food(query)`, `log_food(draft)` (always returns a confirm-sheet to the user, never writes directly), `get_weight_trend()`.

### Safety layer
Pre- and post-generation classifiers: ED-risk patterns, medical-advice boundary (refers to professionals for diagnosis/medication), minimum-calorie floor enforcement, self-harm escalation to resources. Red-team suite runs in CI against the prompt bundle (see testing doc).

## 7. Personalization learning loop

`EntryCorrected` events feed `PersonalizationLearner`:
- **Portion bias:** per (user, food) EW-moving average of corrected/predicted grams; applied as a multiplicative prior when n ≥ 3 and |bias| > 10%.
- **Label remap:** same correction (detected label → chosen food) twice → future scans auto-suggest the remap with a "based on your edits" chip.
- **Usual meals:** scan fingerprint (set of detected labels + phash bucket + time-of-day) matching a past corrected scan ≥ 2× → "Your usual chicken rice order — use previous estimate?" one-tap card.
All priors are per-user, never pooled across users (privacy); aggregate correction *statistics* (anonymized) feed model/prompt evaluation only.

## 8. Quality evaluation & continuous improvement

- **Golden set:** 2,000 weighed-and-photographed meals (800 SEA dishes), versioned in the eval repo. Metrics: detection recall/precision, label top-1/top-3 accuracy, portion MAPE, kcal MAPE, calibration error (ECE).
- **Gate:** any prompt, schema, provider, or model change runs the eval in CI; regressions > 2% on kcal MAPE block merge.
- **Online:** 1% of production scans (consented users) sampled into a human-review queue; correction-rate dashboards per food class in admin.
- **Provider scorecard:** weekly automated benchmark across providers on the golden set + live cost/latency → informs the configured priority order.

## 9. Cost controls

| Lever | Mechanism |
|---|---|
| Dedupe | Perceptual-hash match within 6 h → reuse result free |
| Easy-case routing | Barcode visible / single packaged item → skip vision entirely |
| Image budget | Client resize ≤ 1536 px, ~150 KB; multi-angle capped at 3 frames, video at 6 keyframes |
| Tier quotas | Free: 5 photo scans/day, 10 coach msgs/day; Premium: soft-unlimited with abuse ceiling (config-driven) |
| Model routing | High image-quality + common dish classes → cheaper model tier; degraded quality or composite dishes → frontier model |
| Caching | Coach context, nutrition resolutions, label parses by image hash |
| Metering | `ai_usage_events` → per-user, per-capability cost dashboards; anomaly alerts |
