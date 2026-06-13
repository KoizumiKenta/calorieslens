# CalorieLens AI

**The fastest, smartest AI-powered calorie tracker.** Point your camera at any meal — CalorieLens detects every food on the plate, estimates portions and macros, explains its reasoning, and logs it in seconds. Built to compete with and surpass MyFitnessPal, Lose It!, Cal AI, Cronometer, and Lifesum.

> Photo → Barcode → Label OCR → Voice → Receipt → Menu. Six input modes, one tap to log.

## Repository layout

```
calorielens-ai/
├── docs/                       # All design & planning documents
│   ├── 01-prd.md               # Product Requirements Document, personas, journeys
│   ├── 02-architecture.md      # System architecture, diagrams, event flows
│   ├── 03-database.md          # ER model, design rationale
│   ├── 03-schema.sql           # Full PostgreSQL DDL
│   ├── 04-api/openapi.yaml     # OpenAPI 3.1 specification
│   ├── 05-backend-plan.md      # Laravel implementation plan, module map
│   ├── 06-mobile-architecture.md  # Flutter clean architecture, state mgmt, offline-first
│   ├── 07-ai-services.md       # AI provider abstraction, vision pipeline, RAG, OCR
│   ├── 08-security.md          # Auth flows, security checklist, privacy-by-design
│   ├── 09-testing.md           # Unit / integration / E2E strategy
│   ├── 10-devops.md            # CI/CD, Docker, Kubernetes, monitoring, DR, performance
│   └── 11-business.md          # Monetization, pricing tiers, future roadmap
├── backend/                    # Laravel 12 (PHP 8.4) API + admin
│   ├── app/Domain/             # Domain layer: AI, Nutrition, Recognition, Diary, Coaching
│   ├── app/Http/               # Controllers, requests, resources (API v1)
│   ├── app/Jobs/               # Queued AI pipeline jobs
│   ├── config/ai.php           # Provider configuration & fallback chains
│   └── routes/api.php
├── mobile/                     # Flutter app (Material 3, Riverpod, offline-first)
│   └── lib/
│       ├── core/               # Networking, theme, router, storage, DI
│       └── features/           # Feature-first clean architecture slices
└── infra/
    ├── docker/                 # Dockerfiles, docker-compose for local dev
    ├── k8s/                    # Kubernetes manifests (deployments, HPA, ingress)
    └── .github/workflows/      # CI/CD pipelines
```

## The 30-second pitch

| Competitor pain | CalorieLens answer |
|---|---|
| Manual search & weighing is tedious | AI camera logs a full plate in < 5 s with per-item confidence |
| Photo apps guess wildly | Multi-angle + depth + reference-object scaling, explainable estimates with ranges |
| Western-only databases | Deep SEA regional coverage: hawker food, street food, nasi lemak decomposed into 7 components |
| Black-box AI | Every estimate shows reasoning, confidence %, and a calorie range — never false precision |
| Generic advice | RAG-grounded AI coach personalized on the user's own logs; learns from corrections |

## Quick start (local dev)

```bash
# Backend
cd backend && cp .env.example .env
docker compose -f ../infra/docker/docker-compose.yml up -d   # postgres, redis, minio, mailpit
composer install && php artisan key:generate && php artisan migrate --seed
php artisan serve & php artisan horizon

# Mobile
cd mobile && flutter pub get && flutter run --dart-define-from-file=env/dev.json
```

## Core architectural decisions

1. **Provider-agnostic AI layer** — vision, OCR, STT, and LLM providers sit behind interfaces with health-checked fallback chains (`docs/07-ai-services.md`). Swap OpenAI ↔ Gemini ↔ Claude via config, not code.
2. **Async AI pipeline** — every scan is a queued, event-driven job graph; the mobile app gets results over WebSocket/poll with optimistic UI (`docs/02-architecture.md`).
3. **Nutrition resolver chain** — USDA → Open Food Facts → Nutritionix → Edamam → Spoonacular with per-source priority, Redis caching, and a curated internal DB as source of truth.
4. **Offline-first mobile** — Drift (SQLite) local store, queued mutations, conflict-free sync (`docs/06-mobile-architecture.md`).
5. **Privacy by design** — photos auto-purged after processing unless the user opts in; health data encrypted at rest; regional data residency (`docs/08-security.md`).

## Document reading order

Product → `01-prd.md` · Engineering → `02-architecture.md` → `03-database.md` → `04-api/openapi.yaml` → `07-ai-services.md` · Ops → `10-devops.md` · Business → `11-business.md`
