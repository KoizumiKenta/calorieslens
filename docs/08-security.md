# CalorieLens AI — Security & Privacy

Health-adjacent data (diet, weight, photos of meals) is treated as sensitive throughout. Frameworks: OWASP ASVS L2, MASVS for mobile; compliance targets: PDPA (MY/SG), GDPR-ready, COPPA-style age gate (16+).

## 1. Authentication & session model

```
Login ──► Access JWT (RS256, 15 min, aud/iss pinned, jti)
      └─► Refresh token (opaque 256-bit, SHA-256 stored, 30 d)
              • single-use rotation: each refresh issues a new token in the same family_id
              • reuse detection: presenting a rotated-out token revokes the entire family
                (stolen-token containment) and notifies the user
              • bound to device record; users can list/revoke sessions
```

- Social sign-in: Apple/Google identity tokens verified server-side (issuer, audience, nonce).
- Passwords: Argon2id (memory 64 MB, t=3), HIBP k-anonymity check at set time, min length 10, no composition rules.
- Brute force: 5/min/IP + 10 failures → 15 min account lockout with constant-time responses; CAPTCHA escalation.
- Admin: separate session guard, mandatory TOTP 2FA, IP allowlist option, 8 h absolute session cap.
- JWT keys in KMS; kid-based rotation every 90 days with overlap window.

## 2. Authorization

- Policy-per-model; every query user-scoped at the repository level (no `find($id)` without ownership predicate — enforced by static analysis rule).
- RBAC for admin: `super_admin`, `moderator`, `nutritionist`, `analyst` (read-only PII-masked), `support` (PII-limited). Role grants audited.
- Tier gates (free/premium/family/enterprise) server-side only — client flags are cosmetic.

## 3. Secure media pipeline

1. Client requests scan → server issues **pre-signed PUT** (5 min TTL, content-type + max 10 MB constrained, key namespaced `scans/{user}/{uuid}`).
2. Bucket: private, no public ACLs, SSE-KMS encryption, TLS-only policy.
3. Worker re-validates: magic-byte MIME sniff, image-bomb guard (pixel-count cap before decode), re-encode through libvips (destroys polyglot payloads), EXIF/GPS strip (defense in depth — client strips too).
4. Serving: CDN with signed URLs (15 min) — never direct bucket access.
5. Retention: originals auto-purged 24 h after processing unless user opts into history (`keep_photos`); purge job logs to audit.

## 4. Data protection

| Data | Protection |
|---|---|
| In transit | TLS 1.3 everywhere; HSTS; mTLS for internal service calls (mesh) |
| At rest | Postgres volume encryption + column-level app encryption (libsodium) for: health metrics payloads, chat content, allergy/condition fields |
| Tokens/secrets | Vault/KMS; no secrets in env files in images; sealed-secrets in k8s |
| Mobile | Tokens in Keychain/Keystore (hardware-backed); certificate pinning with remote kill-switch; no sensitive data in logs/screenshots (FLAG_SECURE on paywall/profile optional) |
| Backups | Encrypted, separate KMS key, access logged |
| AI providers | Zero-retention/no-training API tiers required contractually; images sent without user identifiers; provider DPAs on file |

## 5. Privacy by design

- **Minimization:** photos deleted by default; raw provider responses nulled after 7 days; coach grounding stores references, not copies of health data.
- **Purpose limitation:** personalization priors are per-user and never pooled; analytics events pseudonymized with rotating IDs.
- **User rights:** in-app export (full JSON/CSV), deletion (30-day grace, then hard-delete cascade + backup tombstones honored on restore), consent registry per purpose (insights, social, research sampling — all opt-in).
- **Residency:** SEA users pinned to SG region; EU expansion = EU cluster, no cross-region replication of PII.
- **ED safety as privacy concern:** weight projections and deficit framing can be disabled; coach guardrails per AI doc §6.

## 6. API hardening

- Validation: FormRequests on every field, enums server-side, max body sizes, JSON depth caps.
- Rate limits (Redis sliding window): auth 5/min/IP · scans tier-quota'd · search 60/min · coach 10 msgs/min · global 300 req/min/user; 429 + Retry-After.
- Standard injections covered by parameterized Eloquent; raw SQL banned by lint rule except in the search module (reviewed, bound params).
- SSRF: menu-URL fetcher goes through an egress proxy with allowlist of schemes/ports, private-IP blocking, 3 s timeout, response-size caps.
- Webhooks (RevenueCat/Stripe/wearables): signature verification + replay-window nonce store.
- Headers: CSP (admin SPA), X-Content-Type-Options, frame-deny; CORS locked to admin origin (mobile uses no CORS).
- Audit log: auth events, admin actions, data exports/deletions, food edits, permission changes — append-only partitioned table, 2 y retention.

## 7. AI-specific threat model

| Threat | Mitigation |
|---|---|
| Prompt injection via food labels/menus/receipts (OCR text enters prompts) | OCR text wrapped in delimited data blocks with explicit "data, not instructions" framing; output schema validation; coach tools are read-only except the confirm-sheet draft |
| Malicious images (polyglots, decompression bombs) | Re-encode pipeline §3.3 |
| Quota abuse / cost attacks | Per-tier quotas, anomaly detection on `ai_usage_events`, device attestation (Play Integrity / App Attest) required for scan endpoints |
| Model-output harm (dangerous diet advice) | Safety classifiers + calorie floors + red-team CI suite |
| Data exfiltration via coach | Coach context contains only the requesting user's data; tool layer enforces user scoping again |

## 8. Security review checklist (release gate)

- [ ] SAST (Psalm taint + Semgrep ruleset) clean; deps audited (composer audit, `dart pub audit`, Trivy on images)
- [ ] Authn: token rotation + reuse detection tests green; lockout paths verified
- [ ] All new endpoints: policy test + rate-limit test + validation fuzz pass
- [ ] No new raw SQL outside search module; no `find()` without scope
- [ ] Media pipeline re-encode verified on EICAR-style polyglot corpus
- [ ] Secrets scan (gitleaks) on history; k8s manifests pass kube-score / no privileged pods
- [ ] PII flows updated in data map; new data types classified & encrypted as required
- [ ] AI red-team suite pass (injection corpus + ED/medical safety prompts)
- [ ] Pen test findings P1/P2 closed; audit-log coverage for new admin actions
- [ ] Incident-response runbook updated; on-call rotation aware of changes
