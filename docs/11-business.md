# CalorieLens AI — Monetization & Roadmap

## 1. Pricing tiers

| | **Free** | **Premium** (RM 19.90 / $5.99 mo · RM 159 / $47.99 yr) | **Family** (RM 29.90 / $8.99 mo, up to 6) | **Enterprise** (per-seat, annual) |
|---|---|---|---|---|
| Photo AI scans | 5/day | Unlimited* | Unlimited* | Unlimited* |
| Barcode / label OCR / search | Unlimited | Unlimited | Unlimited | Unlimited |
| Voice logging | 3/day | Unlimited | Unlimited | Unlimited |
| Multi-angle, depth, before/after | — | ✓ | ✓ | ✓ |
| AI coach | 10 msgs/day | Unlimited + proactive insights | ✓ | ✓ + cohort programs |
| Weekly meal planner + grocery list | — | ✓ | ✓ shared household plans | ✓ |
| Personalization ("usual order") | basic | full | full | full |
| Wearable sync | 1 source | all sources | all | all + HRIS/wellness integrations |
| Data export | ✓ (always — user right, never paywalled) | ✓ | ✓ | ✓ + org reporting (aggregate only) |
| Streak freezes | 1/mo | 3/mo | 3/mo | — |
| Ads | none (no ads in any tier — trust product) | — | — | — |

*soft cap with abuse ceiling. Free tier is genuinely useful (the funnel is the product); paywall moments: hitting scan cap at dinner, planner preview, insight teasers. Regional pricing (MY/ID/TH PPP-adjusted). Billing: App Store/Play via RevenueCat; Stripe for enterprise.

**Unit economics guardrail:** AI cost target < $0.45/premium user/mo (dedupe + routing per `07-ai-services.md`); free-user AI cost < $0.06/mo (caps), CAC payback < 6 mo.

**Enterprise:** corporate wellness (insurers, employers) — privacy-preserving aggregate dashboards only, individual data never exposed to employers; dietitian console (B2B2C: clients share diaries with their dietitian/PT — read + comment).

## 2. Growth loops

1. Community food submissions → better regional DB → better product → more users (XP rewards).
2. Shared meal cards (beautiful, watermark-lite) → social acquisition.
3. Challenges with friends → invites.
4. Dietitian/PT console → professionals onboard their client base.

## 3. Roadmap

**Now → GA+6 mo** (post-GA backlog from PRD): video scan, receipts, menu analysis, social, challenges, TH locale.

**6–12 mo — Deeper intelligence**
- AI meal planning v2: adaptive plans that replan from actual adherence ("you skipped Tuesday's fish — re-balanced rest of week").
- Nutrition coaching programs: structured multi-week goals (protein habit, sodium reduction) with coach check-ins.
- Micronutrient depth (Cronometer parity) from `food_nutrients_extended`.
- Restaurant partnerships: verified menus for major SEA chains (mamak, kopitiam, fast food).
- On-device lite model for instant pre-labeling (latency + cost) with cloud refinement.

**12–24 mo — Predictive health**
- Predictive insights: weight-trajectory modeling with confidence bands, plateau prediction & pre-emptive coaching, energy/sleep correlation surfacing (wearable fusion).
- CGM integration (Libre/Dexcom) → personal glycemic-response learning per food (regulatory review first; positioned as wellness, not medical).
- Smart-kitchen/scale integrations; meal-kit & grocer partnerships (affiliate revenue).
- Web companion app; tablet/desktop dashboards.
- EU launch (GDPR cluster), MENA halal-focused expansion.

**Principles held through the roadmap:** honesty over precision theater; regional-first database depth; personal data never sold; AI explains itself.
