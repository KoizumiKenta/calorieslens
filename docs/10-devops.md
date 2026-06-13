# CalorieLens AI — DevOps: CI/CD, Containers, Kubernetes, Observability, DR, Performance

## 1. Environments

`local` (docker-compose) → `preview` (PR-scoped namespace, seeded) → `staging` (prod-shaped, synthetic data) → `production` (SG region primary). Infra as code: Terraform (cloud resources) + Helm (app charts); no console changes.

## 2. CI/CD (GitHub Actions — see `infra/.github/workflows/`)

**Backend PR:** lint (Pint) → static analysis (Larastan 9, deptrac) → unit+feature (Postgres/Redis services) → contract check (oasdiff) → AI eval smoke (200 meals, only when `ai/**` paths change) → security (Semgrep, composer audit, gitleaks) → build image → Trivy scan.

**Mobile PR:** analyze → unit/widget/golden → contract DTO tests → build debug.

**Deploy (trunk-based):** merge to `main` → staging auto-deploy (Helm) → smoke E2E (Maestro headless + k6 sanity) → manual approval → production **canary 5% → 25% → 100%** gated on error-rate + p95 SLO queries; auto-rollback on burn-rate breach. DB migrations run as pre-deploy job, expand/contract only (no breaking change within one release).

**Mobile release:** Fastlane lanes — internal track/TestFlight on merge; phased store rollout (1→10→50→100%) with Crashlytics velocity gates; Shorebird/code-push for Dart-only hotfixes where store policy allows.

## 3. Containers (`infra/docker/`)

- Backend image: multi-stage — composer install (no-dev) → PHP 8.4 CLI + Swoole, non-root user, read-only rootfs, ~140 MB. Same image runs api / worker / scheduler via command override (one artifact, three roles).
- Local dev: docker-compose with postgres:16, redis:7, minio, mailpit, meilisearch (optional), reverb.

## 4. Kubernetes (`infra/k8s/`)

| Workload | Scaling | Notes |
|---|---|---|
| `api` | HPA: CPU 60% + custom p95 metric, 3–40 pods | PDB minAvailable 2; topology spread across zones |
| `worker-ai-vision` | KEDA on Redis queue depth (target 5 jobs/pod), 2–60 pods | Sized to provider rate limits via maxReplicas |
| `worker-default` | KEDA, 2–20 | |
| `reverb` (WebSocket) | HPA on connections, sticky via ingress | |
| `scheduler` | 1 replica + lease lock | |
| `admin` | 2 replicas | |

Cluster posture: managed K8s, 3 AZs; NetworkPolicies default-deny; pods non-root, seccomp runtime/default; secrets via External Secrets Operator → cloud KMS; ingress NGINX + cert-manager; image pulls digest-pinned.

Postgres & Redis: managed services (HA, multi-AZ), not in-cluster. Object storage: managed S3-compatible + CDN.

## 5. Observability

- **Metrics:** Prometheus + Grafana. RED per endpoint; queue depth/age; per-provider AI latency/error/cost/breaker-state; business KPIs (scans/min, accept-without-edit rate, correction rate, activation funnel).
- **Tracing:** OpenTelemetry end-to-end — mobile request id → API → queue job → provider call; Tempo backend; 10% head sampling, 100% for errors.
- **Logs:** structured JSON → Loki; PII scrubber processor; 30 d hot / 1 y archive.
- **Errors:** Sentry (backend + Flutter) with release tracking.
- **SLOs:** API availability 99.9% · scan p95 ≤ 6 s · scan success ≥ 98% · WebSocket delivery ≤ 2 s · search p95 ≤ 150 ms. Multi-window burn-rate alerts (PagerDuty); AI cost/user/day anomaly alerts.
- **Synthetics:** scripted scan-with-fixture-image probe every 5 min per region.

## 6. Disaster recovery & backups

| Asset | Strategy | RPO / RTO |
|---|---|---|
| PostgreSQL | Continuous WAL archiving + nightly base backup, cross-region replica; quarterly restore drills (timed, documented) | RPO ≤ 5 min / RTO ≤ 1 h |
| Redis | Persistence off for cache; queues mirrored to DB-backed dead-letter store; rebuildable | RPO: queue ≤ 1 min |
| Object storage | Versioning + cross-region replication (respecting purge obligations — replicas honor deletes) | RPO ≤ 15 min |
| Config/IaC | Git is source of truth; cluster rebuild runbook tested ≤ 4 h | RTO ≤ 4 h |
| RAG/knowledge | Re-ingestable from versioned corpus repo | — |

Failure playbooks: region loss (DNS failover to warm standby, degraded mode: no new scans for ~15 min), provider loss (automatic via fallback chains), data-corruption (PITR + diary reconciliation from client mutation logs — devices hold recent history).

## 7. Performance strategy

**Backend:** Octane keeps framework hot; read-replica routing; dashboard aggregates write-through cached; N+1 banned (automatic detector in CI); partition pruning on all date-ranged queries; pgbouncer pooling.
**AI path:** see cost/latency budgets in `07-ai-services.md` — dedupe, easy-case routing, image budgets.
**Media:** client resize, CDN transforms, AVIF/WebP negotiation, thumbnail pre-warm on scan completion.
**Mobile:** budgets in `06-mobile-architecture.md`; startup tracing in CI (macrobenchmark) failing on >10% regression.
**Capacity model:** 300K MAU ⇒ peak ~120 scans/s, ~900 API rps. Load-test at 5× quarterly.
