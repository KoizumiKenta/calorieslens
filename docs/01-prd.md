# CalorieLens AI — Product Requirements Document

**Version:** 1.0 · **Date:** 2026-06-12 · **Status:** Approved for build

---

## 1. Problem statement

Calorie tracking works — adherence doesn't. 80%+ of users abandon trackers within a month because logging is slow (45–90 s per meal in MyFitnessPal), databases are Western-centric, and AI photo apps (Cal AI) produce unexplained, often wrong numbers that erode trust. The opportunity: make logging take **under 5 seconds**, make estimates **honest** (confidence + ranges + reasoning), and make the database **local-first** for Southeast Asia where no incumbent is strong.

## 2. Goals & success metrics

| Goal | Metric | Target (12 mo post-launch) |
|---|---|---|
| Effortless logging | Median time-to-log a meal | < 5 s (photo), < 3 s (favorite) |
| Trustworthy AI | Median calorie error vs. weighed ground truth | < 20% per meal |
| Retention | D30 retention | > 25% (industry ~10%) |
| Engagement | Meals logged / active user / day | ≥ 2.2 |
| Trust | % AI logs accepted without edit | > 70% |
| Revenue | Free → Premium conversion | 6–8% |
| Scale | Registered users | 2M, 300K MAU |

**Non-goals (v1):** medical-grade tracking (CGM, clinical use), web consumer app, meal delivery, calorie tracking for pets.

## 3. Personas

### P1 — Aisyah, 27, KL marketing exec ("The Local Foodie")
Eats hawker food daily (nasi lemak, chicken rice, laksa). Tried MyFitnessPal — couldn't find half her meals, quit in 9 days. Wants to lose 6 kg without giving up local food. **Needs:** regional database, mixed-dish decomposition, fast photo logging. **Success:** logs lunch at a mamak in one photo, sees nasi lemak broken into 7 components she can edit.

### P2 — Marcus, 34, Singapore software engineer ("The Quantified Optimizer")
Lifts 4×/week, targets 180 g protein. Uses Cronometer but hates manual entry. Skeptical of AI — wants to see the numbers behind the numbers. **Needs:** confidence scores, calorie ranges, explainability, barcode/label OCR, wearable sync, data export. **Success:** scans his meal prep once, saves as template, one-tap logs all week; trusts the app because it says "580–670 kcal, 89% confidence" not "623 kcal".

### P3 — Priya, 42, Penang mother of two ("The Health Rebuilder")
Pre-diabetic, doctor said reduce sugar and sodium. Overwhelmed by nutrition jargon. Cooks at home, shops weekly. **Needs:** plain-language coaching, sodium/sugar alerts, grocery scanner with healthier alternatives, halal-aware suggestions, pantry-to-recipe. **Success:** scans groceries, gets "this soy sauce has 40% less sodium" suggestions; weekly coach summary in simple language.

### P4 — Daniel, 21, university student ("The Budget Gainer")
Bulking on a student budget. Eats at campus stalls and cooks instant meals. **Needs:** budget-aware meal planner, voice logging ("I ate three eggs and two roti canai"), gamification, free tier that's actually useful. **Success:** weekly plan hits 3,100 kcal under RM 60; keeps a 40-day streak for the badge.

### P5 — Admin persona — Lina, nutrition content moderator
Reviews community-submitted barcodes and foods, monitors AI accuracy dashboards, corrects nutrition data. **Needs:** moderation queue with diff views, bulk approve, AI confidence drill-downs, audit trail.

## 4. User journeys (key flows)

### J1 — First scan (activation, target < 3 min from install)
1. Install → 5-screen onboarding: goal, body stats, activity, dietary prefs/allergies, target weight → personalized calorie/macro budget computed (Mifflin-St Jeor + activity + goal rate).
2. Home shows empty diary with a pulsing camera FAB and a "Scan your first meal" coach mark.
3. User photographs lunch. Skeleton card appears instantly (optimistic UI); 2–4 s later the card fills: 3 detected items, portions, confidence chips, total kcal, "Why these numbers?" link.
4. User drags rice portion slider 180 g → 150 g, taps **Log**. Confetti, streak day 1, dashboard rings animate.

### J2 — Hawker meal with decomposition (Aisyah)
Photo of nasi lemak → AI returns dish-level match ("Nasi Lemak, 94%") *and* component breakdown (coconut rice, sambal, egg, anchovies, peanuts, cucumber, fried chicken) each independently editable. Aisyah removes the chicken (didn't order it), total updates instantly. Next time, the app offers "Your usual nasi lemak (no chicken)?" — one tap.

### J3 — Before/after consumption (any persona)
Before photo at meal start; app prompts (optional) for an after photo. Vision diff estimates % consumed per item; diary logs actual intake ("ate 70% of the rice"). User can override.

### J4 — Voice log on the go (Daniel)
Hold mic on FAB: "two boiled eggs and a chocolate protein shake after gym." STT → LLM structuring → 2 entries with quantities, meal slot inferred from time, confirmation sheet → Log.

### J5 — Grocery & pantry (Priya)
Scan barcode → Nutri-grade style A–E rating, allergen flags vs. her profile, "3 lower-sodium alternatives in this category." Photo of fridge contents → identified ingredients → 5 recipe suggestions with per-serving nutrition, filtered halal.

### J6 — Coach conversation (all)
"Can I fit pizza into today's calories?" → coach reads today's log (1,420 of 2,000 kcal used), answers: "Yes — 2 slices of regular-crust margherita ≈ 540 kcal fits your remaining 580. You'd be 18 g short on protein; add a side of grilled chicken or plan a higher-protein breakfast tomorrow." Grounded in the user's data + RAG nutrition knowledge; never invents numbers.

### J7 — Moderation (Lina, admin)
Unknown barcode submitted with label photo → OCR pre-fills nutrition panel → Lina sees photo/extraction side-by-side, fixes sodium, approves → product live globally; submitter gets XP.

## 5. Feature requirements

Priority: **P0** = launch blocker · **P1** = fast follow (≤3 mo) · **P2** = later.

### 5.1 Capture & recognition
| ID | Requirement | Priority |
|---|---|---|
| CAP-1 | Single-photo meal recognition: detect + segment multiple foods, identify each independently | P0 |
| CAP-2 | Per-item estimates: weight/serving, kcal, protein, carbs, fat, fiber, sugar, sodium | P0 |
| CAP-3 | Per-item confidence score, meal-level calorie range, plain-language reasoning | P0 |
| CAP-4 | Full edit before logging: rename (autocomplete), portion slider/stepper, weight, cooking method, remove, add item; totals update < 100 ms locally | P0 |
| CAP-5 | Multi-angle capture (top, side, 45°) with guided UI; backend fuses estimates | P1 |
| CAP-6 | Depth-sensor volume estimation where hardware supports (LiDAR/ToF) | P1 |
| CAP-7 | Video scan: extract 5–8 keyframes, cross-frame fusion for segmentation & portions | P2 |
| CAP-8 | Before/after photos → consumed-fraction estimation per item | P1 |
| CAP-9 | Reference-object scaling: detect spoon/fork/knife/credit card/coin/hand/standard plate, use known dimensions to calibrate portion size | P1 |
| CAP-10 | Mixed-dish decomposition into editable components (nasi lemak, fried rice, curries, pasta, salads, stews, noodle soups) | P0 |
| CAP-11 | Barcode scan (EAN/UPC/QR) → product nutrition incl. ingredients & allergens; unknown → community submission queue | P0 |
| CAP-12 | Nutrition label OCR: rotated/skewed/glare-tolerant; extracts serving size + full panel + ingredients; creates custom food | P0 |
| CAP-13 | Voice logging → structured multi-item entries | P0 |
| CAP-14 | Receipt scan (grocery/restaurant) → suggested diary/pantry items | P2 |
| CAP-15 | Restaurant menu analysis: photo/PDF/URL → per-dish estimates + lighter-option recommendations | P2 |
| CAP-16 | Manual search with typo-tolerant autocomplete (< 150 ms p95), verified-entry badges, recent/frequent ranking | P0 |

### 5.2 Diary & data
| ID | Requirement | Priority |
|---|---|---|
| DIA-1 | Diary by meal slot (breakfast/lunch/dinner/snacks) + timeline view; daily macro totals | P0 |
| DIA-2 | Favorites: one-tap re-log | P0 |
| DIA-3 | Meal templates (multi-item bundles), one-tap log | P0 |
| DIA-4 | Copy meal/day, move between slots, swipe delete with undo | P1 |
| DIA-5 | Weight log with progress charts, 7-day rolling average, monthly trend, projection from sustained calorie balance (with honest uncertainty band) | P0 |
| DIA-6 | Water tracking with goal + smart reminders | P0 |
| DIA-7 | Exercise log (walk/run/cycle/swim/weights/HIIT/yoga) with MET-based burn estimates; optional calorie-budget adjustment | P1 |
| DIA-8 | Wearable sync: Apple Health, Health Connect, Garmin, Fitbit — steps, active kcal, HR, sleep, workouts; auto-adjust targets | P1 |
| DIA-9 | Data export (CSV/JSON) and account deletion (GDPR/PDPA) | P0 |

### 5.3 Intelligence & coaching
| ID | Requirement | Priority |
|---|---|---|
| AI-1 | Conversational coach grounded in user logs + RAG nutrition corpus; refuses to fabricate; cites uncertainty | P0 |
| AI-2 | Proactive daily insights (low protein, high sodium, skipped meals, weekend overage patterns, no water logged) — max 2/day, quiet hours respected | P1 |
| AI-3 | Personalized learning from corrections: per-user food/portion priors, "your usual order" suggestions | P1 |
| AI-4 | Weekly meal planner: calorie target, budget, cuisine, cook time, protein, restrictions → 7-day plan + grocery list | P1 |
| AI-5 | Grocery scanner: nutrition grade, healthier alternatives, allergen warnings, macro comparison | P1 |
| AI-6 | Pantry photo → ingredient list → recipe suggestions with nutrition | P2 |
| AI-7 | Explainability everywhere: every AI number tappable to reasoning; ranges shown when confidence < 90% | P0 |

### 5.4 Database & content
| ID | Requirement | Priority |
|---|---|---|
| DB-1 | Regional database: Malaysian, Singaporean, Indonesian, Thai, Chinese, Japanese, Korean, Indian, Western, Middle Eastern — incl. hawker/street food, local beverages (teh tarik, kopi variants, Milo), traditional desserts (kuih, chendol) | P0 |
| DB-2 | Multi-source resolution: USDA FDC, Open Food Facts, Nutritionix, Edamam, Spoonacular — prioritized, cached, fallback | P0 |
| DB-3 | Verified-entry program + community submissions with moderation | P0 |
| DB-4 | Multi-language food names & search (EN, MS, ZH, ID, TH at launch) | P1 |

### 5.5 Engagement & social
| ID | Requirement | Priority |
|---|---|---|
| ENG-1 | Streaks (daily/weekly), achievement badges, XP & levels; streak freeze (1/mo free, more for premium) | P1 |
| ENG-2 | Goal-based challenges (protein, water, weight milestones), community challenges | P2 |
| ENG-3 | Social: share meal cards, follow friends, groups, streak comparison — private by default, granular controls | P2 |

### 5.6 Profile & platform
| ID | Requirement | Priority |
|---|---|---|
| PRO-1 | Profile: age, gender, height, weight, goal weight, activity level, dietary prefs (vegan/vegetarian/halal/keto/paleo/gluten-free/low-carb), allergies, fitness goal | P0 |
| PRO-2 | Dark + light mode, Material 3, accessibility (TalkBack/VoiceOver, dynamic type, ≥4.5:1 contrast) | P0 |
| PRO-3 | Offline-first: full diary read/write offline; scans queue and process on reconnect | P0 |
| PRO-4 | Admin portal: user mgmt, food DB mgmt, moderation queue, AI confidence monitoring, nutrition corrections, analytics, reports, AI usage stats | P0 |

## 6. UX principles

1. **Camera is the home key.** The FAB is the AI camera; every input mode (barcode, label, voice, receipt, menu) is one swipe inside the capture sheet.
2. **Honest numbers.** Never display false precision. Confidence < 90% → show range. Every figure taps through to reasoning.
3. **Edit-first, not error-first.** AI output is a draft the user confirms in one tap or tweaks in two. Corrections are gifts — feed them back to personalization.
4. **Five-second rule.** Any logging flow exceeding 5 s of user effort is a bug.
5. **Optimistic everything.** Log instantly to local store; sync in background; never block on network.
6. **Coach, don't scold.** Insights are framed as next actions ("add a palm-size of chicken at dinner"), never judgments. Eating-disorder safeguards: no aggressive deficit targets (floor at BMR × 0.85), opt-out of weight projections, supportive language review.

## 7. Acceptance criteria samples (P0)

- **CAP-1/2/3:** Given a clear photo of 3 distinct foods, ≥ 90% of trials detect all 3; each item shows name, grams, kcal, 4+ macros, confidence %; meal total shows kcal range. End-to-end p95 latency ≤ 6 s.
- **CAP-12:** Given a label photographed at ≤ 30° rotation with moderate glare, serving size + 7 nutrients extracted with ≥ 95% field accuracy; user can correct any field before save.
- **PRO-3:** With airplane mode on, user can search (local cache), log, edit, and view diary; on reconnect, all mutations sync within 30 s with no data loss; photo scans queue and complete.
- **AI-1:** Coach answers about user data reference only actual logged values; when data is missing it says so; harmful-advice red-team suite passes (no sub-1200 kcal recommendations, no ED-pattern reinforcement).

## 8. Release plan

| Phase | Scope | Timeline |
|---|---|---|
| Alpha | P0 capture (photo, barcode, OCR, voice, search), diary, profile, dashboard, admin basics — internal + 200 testers (MY/SG) | M0–M3 |
| Beta | Coach, weight/water, regional DB v1 (5,000 curated local foods), personalization v1, wearables | M3–M5 |
| GA | Stores launch MY/SG/ID, premium tier, multi-angle, before/after, planner | M5–M7 |
| Post-GA | Video scan, receipts, menus, social, challenges, TH/EN-global expansion | M7–M12 |

## 9. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Vision accuracy below trust threshold | Ground-truth eval set (2,000 weighed meals incl. 800 SEA dishes) gating every model/prompt change; fallback to ranked suggestions UI when confidence < 60% |
| AI provider cost blowout | Per-tier quotas, response caching, small-model routing for easy cases, image downscaling, provider arbitrage via abstraction layer |
| Provider outage | Health-checked fallback chains across 3 vision providers; graceful degradation to search-first logging |
| Regional DB cold start | Curated seed (licensed MY/SG nutrient tables + dietitian review) + community flywheel with XP incentives + moderation |
| ED/health harm | Safeguards in §6; coach red-teaming; resources surfaced on risk signals; age gate 16+ |
| Privacy backlash (food photos = sensitive) | Default photo deletion post-processing, on-device pre-processing where possible, transparent data page, regional residency |
