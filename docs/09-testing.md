# CalorieLens AI — Testing Strategy

Principle: the AI is non-deterministic; everything around it must be deterministic and the AI itself is tested *statistically* against golden datasets, not with exact-match assertions.

## 1. Test pyramid

| Layer | Tooling | Scope | Gate |
|---|---|---|---|
| Backend unit | Pest | Domain services, value objects, portion fusion math, label parser, resolver chain (fake adapters) | PR, < 3 min |
| Backend feature | Pest + RefreshDatabase (Postgres in CI, never SQLite — partitions/trgm/vector must match prod) | Every endpoint: happy path, authz, validation, idempotency, rate limit | PR |
| Contract | oasdiff + Spectral; Prism mock server vs Flutter DTO tests | OpenAPI ↔ implementation ↔ mobile serializers | PR |
| Integration | Testcontainers (Redis, MinIO); provider adapters vs recorded fixtures (VCR-style cassettes) | Pipeline end-to-end with faked providers; queue/retry/failure paths | PR |
| Mobile unit/widget | flutter_test + golden_toolkit | Use cases, controllers (Riverpod overrides), design-system goldens, scan-card states | PR |
| Mobile integration | integration_test on Firebase Test Lab (6-device matrix) | Critical paths incl. airplane-mode offline sync | nightly |
| E2E | Maestro flows against staging | install→onboard→scan(stubbed AI)→log→dashboard; barcode; voice; coach | nightly + pre-release |
| Load | k6 | scan burst (5× expected peak), diary sync storm after offline, search p95 | weekly + pre-release |
| Chaos | scripted drills | kill vision provider (expect fallback), Redis loss, replica lag | monthly |

## 2. AI quality testing (the differentiator)

- **Golden meal set:** 2,000 weighed/photographed meals (800 SEA), labeled by dietitians; stored with per-item ground truth grams + nutrition. Versioned (DVC).
- **Eval harness** (`backend/tests/Eval/`): runs the full recognition pipeline with live providers against the set; produces detection P/R, label top-1/3, portion MAPE, kcal MAPE, expected calibration error; per-cuisine breakdowns.
- **CI gate:** any change to prompts, schemas, fusion weights, or provider config runs a 200-meal smoke subset; > 2% kcal-MAPE regression blocks merge. Full set nightly.
- **OCR corpus:** 500 label photos (rotated/glare/crumpled/multilingual) with field-level ground truth; ≥ 95% field accuracy gate.
- **Voice corpus:** 300 utterances (EN/MS/Manglish/Singlish mixes) → structured-output exactness.
- **Coach red-team suite:** ~400 adversarial prompts (ED bait, medical overreach, injection-in-OCR, data-exfil attempts) → classifier + rubric-scored by LLM judge with human spot-audit; zero-tolerance categories block release.
- **Online monitoring as testing:** correction-rate per food class, accept-without-edit rate, confidence calibration drift — alerts when production diverges from eval expectations.

## 3. Conventions

- Factories for every model; scenario builders (`UserBuilder::premium()->withDiaryDays(7)`).
- Provider fakes ship with each domain (`AIManager::fake()->visionReturns(...)`) so feature tests never touch networks.
- Mutation testing (Infection) on the money paths: portion fusion, nutrition math, target computation — ≥ 80% MSI.
- Flaky test policy: quarantine label + 48 h fix-or-delete.
- Coverage gates: domain 90%, overall 75% — coverage is a floor, not a goal.
