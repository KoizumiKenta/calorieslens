# CalorieLens AI — Backend Implementation Plan (Laravel 12 / PHP 8.4)

## 1. Architectural style

Modular monolith, domain-first. Controllers are thin HTTP adapters; all behavior lives in domain services invoked via actions. SOLID applied pragmatically: contracts at module boundaries and provider seams, not interface-per-class ceremony.

```
backend/
├── app/
│   ├── Domain/                      # framework-light business logic
│   │   ├── AI/                      # provider abstraction (contracts, adapters, resilience)
│   │   ├── Nutrition/               # resolver chain, source adapters, validation
│   │   ├── Recognition/             # scan pipeline stages, portion fusion, decomposition
│   │   ├── Diary/                   # logging, totals, favorites, templates
│   │   ├── Coaching/                # RAG, context builder, insights, safety
│   │   ├── Tracking/                # weight, water, exercise, health sync, targets
│   │   ├── Personalization/         # priors, learners
│   │   ├── Gamification/            # streaks, XP, achievements
│   │   ├── Planner/                 # meal plan generation
│   │   └── Shared/                  # value objects (NutritionFacts, Grams, Confidence), events
│   ├── Http/
│   │   ├── Controllers/Api/V1/      # one controller per resource
│   │   ├── Requests/                # FormRequest validation, all input
│   │   ├── Resources/               # API response shaping (matches OpenAPI)
│   │   └── Middleware/              # auth, tier quota, idempotency, locale
│   ├── Jobs/                        # queued pipeline jobs (per stage where retried independently)
│   ├── Listeners/                   # domain event consumers
│   ├── Models/                      # Eloquent, thin: casts, scopes, relations only
│   └── Console/                     # scheduled commands
├── config/ai.php                    # provider chains, quotas, model routing
├── database/migrations/             # mirrors docs/03-schema.sql
├── routes/api.php                   # v1 routes
└── tests/{Unit,Feature,Integration}
```

Rules enforced by `deptrac` in CI:
- `Domain/*` may not import `Http/*` or facades other than Log/Event/Cache contracts (constructor-injected).
- Cross-domain calls go through the other domain's service contract or events — never its models.
- `Models` are owned by exactly one domain.

## 2. Key runtime components

| Concern | Choice | Notes |
|---|---|---|
| App server | Octane (Swoole) | Stateless; watch for static-state leaks in providers (CI smoke test) |
| Auth | JWT access (15 min, RS256) + opaque rotating refresh (30 d, family reuse-detection) | `php-open-source-saver/jwt-auth` or first-party implementation per security doc |
| Queues | Redis + Horizon | Queues: `ai-vision` (dedicated pool), `ai-ocr`, `notifications`, `default`, `low` (exports, archival) |
| Realtime | Laravel Reverb | Private channels `user.{id}`; events: `scan.ready`, `plan.ready`, `insight.created` |
| Scheduler | Laravel scheduler in dedicated pod | Insights aggregation (hourly per-timezone cohort), partition creation, media purge, provider scorecard, streak-freeze sweep |
| Search | Postgres FTS + pg_trgm behind `FoodSearchContract` | Meilisearch adapter ready when needed |
| Admin | Inertia + Vue 3, separate `admin` guard, mandatory TOTP 2FA | |
| API docs | Generated from attributes → validated against `docs/04-api/openapi.yaml` in CI (oasdiff) | |

## 3. Request lifecycle conventions

1. **Validation** — FormRequest; all enums via PHP 8.4 backed enums shared with resources.
2. **Authorization** — policies per model + tier gate middleware (`RequiresTier:premium`) + quota middleware (Redis sliding window per capability).
3. **Idempotency** — `Idempotency-Key` header on POSTs stored 24 h in Redis (response replay); diary additionally idempotent by `client_uuid`.
4. **Action execution** — single-purpose action classes (`LogDiaryEntries`, `CreateScan`, `CorrectScanItem`) returning domain DTOs.
5. **Response** — API Resources, RFC 9457 errors via a single exception renderer.

## 4. The scan pipeline as jobs

```
CreateScan (sync, API)            → returns signed URLs
ProcessMealPhotoJob (ai-vision)   → preprocess → vision (FallbackChain) → decompose
  └─ on items resolved            → ResolveNutritionJob (chained, same worker)
  └─ persist ScanResult           → broadcast scan.ready
LearnFromCorrectionJob (default)  → personalization priors
PurgeMediaJob (scheduled)         → privacy deletion
GenerateMealPlanJob (low)         → planner
BuildDailyInsightsJob (scheduled) → cohort-batched, per-timezone
```

Retry policy: vision job `tries=3`, `backoff=[5,15,60]`, failure → scan `status=failed` + apologetic push with search fallback CTA. Jobs are idempotent (keyed on scan id, stage).

## 5. Implementation phases

| Phase | Weeks | Scope |
|---|---|---|
| 0 — Foundation | 1–2 | Repo, CI, Docker, Octane skeleton, auth (register/login/refresh/rotation), profiles + target computation, RBAC, audit log |
| 1 — Food core | 3–5 | Schema migration, food graph, search, barcode lookup chain, custom foods, nutrition resolver + 5 source adapters, seed importer (USDA + OFF + curated MY/SG set) |
| 2 — Scan pipeline | 5–8 | Media upload flow, AI abstraction + 3 vision adapters, full pipeline stages, corrections API, WebSocket events, OCR pipeline, voice flow |
| 3 — Diary & tracking | 8–10 | Diary CRUD + batch sync, favorites, templates, dashboard aggregates, weight/water/exercise, health sync |
| 4 — Intelligence | 10–13 | RAG ingestion, coach (SSE streaming + tools + safety), insights engine, personalization learners |
| 5 — Engagement & admin | 13–15 | Gamification, moderation queue, admin panel modules, subscriptions/webhooks |
| 6 — Hardening | 15–17 | Load tests, chaos drills (provider outage), security review, pen test fixes, eval-gated prompt tuning |

## 6. Coding standards

- PHP 8.4, strict types everywhere, readonly DTOs, enums over string constants.
- Larastan level 9, Pint (PSR-12), Rector on PHP-version upgrades.
- Every domain service has a contract + fake for testing (`AIManager::fake()` ships with the module).
- No business logic in models, controllers, or blade/Inertia layers.
- Database changes only via migrations; destructive migrations require a two-deploy expand/contract pattern.
