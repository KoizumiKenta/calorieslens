# CalorieLens AI — Flutter Mobile Architecture

Flutter (stable channel), Material 3, feature-first clean architecture, Riverpod for state, Drift (SQLite) for offline-first storage. Min targets: iOS 16, Android 8 (API 26); camera/depth features degrade gracefully.

## 1. Folder structure

```
mobile/lib/
├── main.dart                        # bootstrap: DI, env, error handlers
├── app.dart                         # MaterialApp.router, theming, locale
├── core/
│   ├── config/                      # env, feature flags, remote config
│   ├── network/                     # Dio client, auth interceptor, retry, SSE/WebSocket
│   ├── storage/                     # Drift database, secure storage (tokens)
│   ├── sync/                        # mutation queue, sync engine, connectivity
│   ├── router/                      # go_router config, guards, deep links
│   ├── theme/                       # M3 ColorScheme (seed), typography, dark/light
│   ├── l10n/                        # ARB files: en, ms, zh, id, th
│   ├── widgets/                     # skeleton loaders, empty states, confidence chip,
│   │                                #   nutrition ring, range bar, edit sheet primitives
│   └── utils/                       # units, date/tz, formatters
├── features/                        # each: data/ domain/ presentation/
│   ├── onboarding/
│   ├── capture/                     # camera, barcode, label, voice, multi-angle, video
│   ├── scan_review/                 # AI result card, item editing, decomposition UI
│   ├── diary/
│   ├── dashboard/
│   ├── foods/                       # search, detail, custom food form
│   ├── coach/                       # chat (streaming), insights
│   ├── tracking/                    # weight, water, exercise, health sync bridge
│   ├── planner/
│   ├── gamification/
│   ├── social/
│   ├── profile/
│   └── paywall/
└── shared/                          # cross-feature domain models (NutritionFacts, FoodRef)
```

Each feature slice:
```
features/scan_review/
├── data/        # DTOs, API + local data sources, repository impl
├── domain/      # entities, repository contract, use cases (pure Dart, no Flutter)
└── presentation/# controllers (Riverpod Notifiers), screens, widgets
```
Dependency rule: presentation → domain ← data. `domain/` imports nothing from Flutter or data.

## 2. State management — Riverpod 2 (codegen)

- **Why Riverpod over Bloc:** compile-safe DI + state in one graph; `AsyncNotifier` covers our dominant pattern (async resource + optimistic mutation) with less ceremony; easy provider overrides make widget/unit tests cheap.
- Conventions: one `@riverpod` controller per screen; repositories and services are `@Riverpod(keepAlive: true)`; streams from Drift watch queries drive reactive UI (diary screen rebuilds from the local DB, not from network responses).
- Side-effect pattern: controller method → optimistic local write → enqueue mutation → state already updated via Drift stream. Network errors never roll back UI; the sync engine reconciles.

## 3. Offline-first design

**Source of truth on device = Drift.** The server is the sync authority.

| Data | Local store | Sync direction |
|---|---|---|
| Diary entries, water, weight, exercise | `diary_*` tables | bidirectional |
| Favorites, templates, profile | tables | bidirectional |
| Food cache (recently used/searched ~5k rows + top regional foods bundle) | `food_cache` | pull-through |
| Scan queue (photos awaiting upload) | `pending_scans` + files dir | push |
| Coach history | `chat_*` | pull (write-through online only) |

**Mutation queue:** every local write appends `{id, entity, op, payload, client_uuid, created_at}` to `mutations`. Sync engine drains FIFO on connectivity, batching diary ops into `POST /v1/diary/entries`. Server idempotency by `client_uuid` makes retries safe. Conflict policy: per-field last-write-wins with server timestamps; diary conflicts are rare (single-user data) — true conflicts surface a non-blocking "we kept the newer edit" toast.

**Offline scans:** photo captured offline → stored locally, card shows "queued — will analyze when online"; user may log a manual estimate immediately which the scan later *suggests updating* (never silently overwrites a user-entered value).

## 4. Capture stack

- `camera` plugin with custom capture UI; guided multi-angle overlay (top/side/45° silhouettes); torch + macro hints from image-quality heuristics run on-device (blur/exposure via simple luma stats) so users retake *before* spending an AI call.
- Barcode: `mobile_scanner` (MLKit/AVFoundation) — on-device, instant, offline-capable against the cached product table.
- Depth: platform channels — ARKit `sceneDepth` / ARCore Depth API where available; depth PNG uploaded alongside the photo.
- Voice: `record` plugin → Opus; push-to-talk UX with live waveform.
- All uploads: client-side resize to ≤1536 px, EXIF strip, background `workmanager` upload with resume.

## 5. Signature UX details

- **Floating AI camera FAB** center-docked in the M3 NavigationBar (Home, Diary, ▢Camera, Coach, Profile); long-press fans out mode shortcuts (barcode/label/voice).
- **Scan review card:** items listed with confidence chips (●●● ≥90% green, 70–89% amber with range shown, <70% red with "check this" prompt), bbox overlay toggle, per-item bottom-sheet editor (portion slider with haptic detents at common servings, cooking-method segmented control), composite dishes shown as expandable component trees. Totals animate on every edit (<100 ms, computed locally from cached per-100g values).
- **"Why these numbers?"** expands per-item reasoning verbatim from the API.
- Skeleton loaders for every async surface; Lottie micro-celebrations (streaks, goals) with reduced-motion respect; pull-to-refresh on diary/dashboard; full RTL + dynamic type + semantics labels (a11y audited each release).

## 6. Performance budget

| Metric | Budget |
|---|---|
| Cold start → first frame | < 1.8 s (deferred init: analytics, health bridge lazy) |
| Diary day render | < 16 ms/frame from Drift watch |
| Capture shutter → skeleton card | < 300 ms |
| App size | < 35 MB per ABI (deferred components for Lottie packs / regional food bundle) |

## 7. Testing on mobile

- Domain/use cases: pure Dart unit tests.
- Controllers: Riverpod overrides + fake repositories.
- Widgets: golden tests for the design system + the scan review card states (loading/low-confidence/composite/error).
- Integration: `integration_test` on Firebase Test Lab device matrix; offline-mode E2E (airplane-mode toggles) in the critical-path suite.
- Contract: DTO serializers verified against `docs/04-api/openapi.yaml` examples in CI.
