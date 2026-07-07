# CareerPulse — Build Template for a Career-Learning App

> **What this file is:** a reusable, career-agnostic specification for building a
> "knowledge-map learning app" — the proven TechPulse formula — for ANY profession.
> Hand this file to an AI coding agent (Claude Code recommended) together with a
> filled-in **Career Pack** (§4) and say:
>
> *"Read CareerPulse-Template.md. Build the app for the {CAREER} pack in §4,
> milestone by milestone, testing each milestone before moving on."*
>
> Reference implementation: TechPulse (this repository) — AI/tech career, iOS 26,
> SwiftUI + SwiftData + on-device Foundation Models. All architecture below is
> proven working there.

---

## 1. The Product Formula (career-independent)

People preparing for or growing in a career drown in scattered content and have
no picture of what they don't know. This app fixes that with four loops:

1. **Curated feed** — articles/updates from trusted {CAREER} sources, cached
   offline, summarized on-device.
2. **Knowledge map** — the profession's skill tree: ~50 concepts in 5–8
   clusters with prerequisite arrows. Gray = new, blue = learning, green = known.
   Reading and quizzing "lights up" the map.
3. **Gap detector** — computes the "frontier" (concepts whose prerequisites are
   lit) and tells the user exactly what to learn next and which article fills it.
4. **Retention loop** — weekly on-device quizzes (+mastery), time decay
   (spaced repetition), streaks, staged learning path ("You are here").

The emotional hook: *day one shows the full map of a professional — mostly dim.
Every day of use visibly lights it up.* Progress you can SEE beats progress you
are told about.

## 2. Architecture (copy from TechPulse — it works)

```
SwiftUI Views:  Feed · Article · Knowledge (clusters → dependency graph)
                · Progress (path + charts) · Quiz · Onboarding · Settings
      │ @Query / @Observable
App Services:   FeedSyncService (concurrent RSS fetch, offline cache, pruning)
                IntelligenceService (on-device summarize + concept extraction,
                                     vocabulary-matching fallback)
                KnowledgeEngine (mastery scoring, decay, co-occurrence links)
                KnowledgePathEngine (frontier, gap detection, recommendations)
                QuizEngine (on-device generation + template fallback)
      │
SwiftData:      FeedSource · Article · Concept · ConceptLink ·
                ConceptDependency · LearningEvent
```

**Mastery rules (tuned in production):** new = 0.1 · article read = +0.1 ·
"I know this" = 1.0 · quiz passed = +0.3 · decay −0.05/month unreviewed
(floor 0.8 for user-marked known). "Lit" = state ≠ new.

**Frontier rule:** a pack concept is "ready to learn" when ALL its prerequisite
arrows point at lit concepts. Restrict frontier to pack concepts only — never
recommend stray extracted terms.

**Platform notes:** iOS 26+, Swift 6 strict concurrency, XcodeGen project,
Foundation Models for AI with a vocabulary-matching fallback so the app is
fully functional without Apple Intelligence. Android port: Kotlin + Room +
Gemini Nano follows the same service boundaries.

## 3. Milestones (build order — verify each before the next)

1. **M1 Skeleton** — models, tab navigation, seeded sources, design tokens.
2. **M2 Feed** — RSS/Atom parsing, offline cache, article view, background refresh.
3. **M3 Intelligence** — on-device summaries + concept extraction, fallback path.
4. **M4 Knowledge Engine** — mastery, "I know this" sheet, decay, embedding dedupe.
5. **M5 Visualization** — force-directed graph (Canvas), Swift Charts progress.
6. **M6 Polish** — quiz mode, onboarding, Siri intent, app icon, haptics, pruning.
7. **M7 Career Pack** — seed §4's clusters/concepts/dependencies; cluster
   overview with GAP badge; frontier rings; "YOUR NEXT DOT" feed banner;
   staged learning path.
8. **Testing gate at every milestone** — unit tests for parser + engines,
   UI-test journey that screenshots every screen (feed → article → concept →
   graph → quiz → result). Ship nothing that isn't click-verified.

## 4. The Career Pack (the ONLY part you rewrite per career)

Fill these five blocks. Everything else is reused unchanged.

### 4.1 Identity
```yaml
career: "{e.g. Registered Nurse}"
app_name: "{e.g. PulsePoint}"
tagline: "The map of a professional {career}. Light it up."
accent_domain_color: "{one hue that fits the field — see §7}"
```

### 4.2 Clusters (5–8, with a reading order and one "specialty lane")
Example — **Registered Nurse**:
`Anatomy & Physiology → Pharmacology → Clinical Skills → Patient Assessment →
Acute Care → Ethics & Law · specialty lane: “Your Unit” (ICU/ER/Peds…)`

Example — **Financial Analyst (CFA track)**:
`Quantitative Methods → Economics → Financial Statements → Corporate Finance →
Equity & Fixed Income → Derivatives & Alts → Ethics · lane: “Your Sector”`

Example — **UX Designer**:
`Design Foundations → Research Methods → Interaction Design → Visual & Motion →
Prototyping & Tools → Design Systems → Career Craft · lane: “Your Platform”`

### 4.3 Concepts table (~50 rows; each row = a dot)
| Concept | Cluster | One-line beginner definition | Prerequisites |
|---|---|---|---|
| e.g. Beta-blockers | Pharmacology | Drugs that slow heart rate and lower blood pressure. | Cardiovascular system |

Rules: definitions must be quiz-usable (the fallback quiz asks "which concept
does this describe"). Prerequisites form a DAG — no cycles. 
Stage the concepts into 5–6 dependency-ordered stages for the learning path.

### 4.4 Feed sources (6–12 RSS/Atom feeds, user-editable)
Pick institutional, high-signal sources. Examples:
- Nurse: NIH/CDC updates, AJN, Medscape Nursing, NursingCenter, unit-specific journals
- Finance: SEC press, FT/Bloomberg RSS (where licensed), CFA Institute blog, central-bank feeds
- Law: SCOTUSblog, court press feeds, bar-association journals, Justia summaries
- UX: NN/g, Smashing Magazine, design-systems blogs, HIG/Material updates
⚠️ Only publicly published feeds. Respect robots/ToS; never scrape paywalls.

### 4.5 Seed of the user's existing knowledge
Onboarding step: "mark what you already know" per cluster (chips) — the
career equivalent of TechPulse's resume seeding. Ship green dots on day one;
an all-gray map demoralizes experienced users.

## 5. Business Plan Skeleton

- **Positioning:** "Duolingo-style visible progress for {career}, built on real
  industry news — private by design, works offline."
- **Model:** free core (feed + map) → **Pro subscription** (quiz mode, multiple
  specialty lanes, insights) at $4–8/mo → **Pack marketplace**: each career pack
  is a product; domain experts author packs for revenue share.
- **B2B second act:** hospitals/firms/schools buy seats; the pack becomes their
  onboarding curriculum; aggregate-only, opt-in progress reporting (never
  individual surveillance — see §6).
- **Moat:** pack quality + the dependency graph. Anyone can list articles;
  a *correct prerequisite graph per profession* is expert work — that's the asset.
- **Validation order:** 1 career (pick one with exam pressure: nursing NCLEX,
  CFA, bar exam, PMP) → 50 users → retention ≥ 4 opens/week before pack #2.
- **Regulated-field caveats:** medical/legal/financial packs need an expert
  reviewer per release + in-app disclaimer ("educational, not professional
  advice"); never generate dosage/legal/investment advice via AI — quiz only
  from the vetted pack definitions.

## 6. Privacy & Security (non-negotiables)

**Data minimization is the product's selling point. Keep it absolute.**

- **No accounts, no server, no analytics SDKs.** All state in the on-device
  database. The only network traffic is fetching public feeds over HTTPS (ATS
  enforced, no exceptions). App Store privacy label: "Data Not Collected".
- **On-device AI only** (Foundation Models / Gemini Nano). Article text and the
  user's knowledge profile never leave the phone. A knowledge map is a
  *capability profile* — treat it like health data.
- **Prompt-injection defense:** feed content is untrusted input that flows into
  an LLM. Instructions must be system-side only; strip HTML; cap lengths;
  structured output (@Generable) so the model can only return typed fields —
  never free text that becomes UI or actions.
- **Parser hardening:** XML parser with entity expansion off (no billion-laughs),
  size caps per feed, per-item length caps, scheme allowlist (https only).
- **If sync/backup is ever added:** end-to-end encrypted (CloudKit private DB or
  equivalent), opt-in, exportable, deletable. GDPR/CCPA are then in scope:
  export = one JSON file; delete = wipe container.
- **B2B rule:** report only cluster-level, aggregated, opt-in progress.
  Selling individual employee knowledge maps to employers kills the product's
  trust story (and in the EU, likely its legality).
- **Supply chain:** zero third-party dependencies is a feature — keep it.
  Signed releases, no remote config, no dynamic code.

## 7. One App for Everyone (gender & inclusivity)

**Ship ONE app, not a "male" and "female" version.** Research and market
history are clear: "shrink it and pink it" products underperform and insult
users. What actually differs is *aesthetic preference distribution*, and the
fix is **personalization, not segregation**:

- **Theme picker in onboarding** (and Settings): 4–6 accent palettes on the
  same neutral chassis, e.g. `Ocean (blue/green — TechPulse default) · Plum
  (violet/rose) · Forest (green/amber) · Mono (black/white) · Sunset
  (coral/gold)`. Mastery states stay semantically consistent (dim → mid →
  "known") in every palette; check all palettes for color-blind safety
  (deuteranopia ≈ 8% of men — avoid red/green-only distinctions; TechPulse's
  gray/blue/green passes because lightness also differs).
- **Neutral chassis:** cool-white background, one type family, geometry over
  ornament. Nothing in the layout codes gendered.
- **Language:** "you/your map" voice; example personas and names in marketing
  span genders; career packs avoid gendered defaults (nurses aren't "she",
  engineers aren't "he").
- **Accessibility = inclusivity:** Dynamic Type (the text-size setting),
  VoiceOver labels on graph nodes, ≥44pt touch targets, reduced-motion mode
  that freezes the force simulation.

## 8. Prompts to drive an AI coding agent

- **Kickoff:** "Read CareerPulse-Template.md. Scaffold M1 for the {career} pack
  in §4 on iOS 26/SwiftUI/SwiftData with XcodeGen. Build and run the simulator
  before finishing."
- **Per milestone:** "Continue with M{n}. Write unit tests for the new engine
  logic and extend the UI-test journey; run the full suite and show me
  screenshots."
- **Pack authoring:** "Here are my {career} clusters and concepts (paste §4).
  Validate the prerequisite graph is acyclic, definitions are quiz-usable, and
  generate SeedData from it."
- **Design:** "Match the screens to the design mockups in design/ — cool-white
  cards, mastery colors, ≥44pt targets. Verify with screenshots at 120px and
  full size."
- **Review gates:** "Run a security pass over parser and AI-input paths per §6."

## 9. Future feature roadmap (validated next bets)

1. **Widgets + Live Activity** — streak & next-dot on the home/lock screen (retention).
2. **Import your syllabus/resume** — on-device extraction seeds green dots (the
   TechPulse resume trick, generalized).
3. **Spaced-repetition scheduler** — decay already exists; surface "3 concepts
   fading — 2-minute review?" notifications (local notifications only).
4. **Pack marketplace + expert authoring tool** — the business engine.
5. **Mock-exam mode** — timed, blueprint-weighted quizzes for exam careers
   (NCLEX/CFA/bar) — the strongest willingness-to-pay feature.
6. **Shareable map card** — an image of your lit constellation (brag loop; no
   data leaves except what the user explicitly shares).
7. **iPad/Mac layout** — the graph deserves a big canvas.
8. **CloudKit E2E sync** — multi-device, still no server of yours.
9. **Cited summaries** — summary sentences link back to article paragraphs
   (hallucination guard, big trust win in regulated fields).
10. **Team/classroom mode** — aggregate cluster heatmap for a cohort (opt-in,
    anonymized; see §6).

## 10. Universal App Mode — one app, any career, customized on the phone

Instead of shipping one app per career, ship ONE app where the pack is created
at runtime. Everything career-specific is already data, so this is an
onboarding flow, not a rewrite:

**Onboarding becomes a 4-step wizard:**
1. **Career** — free-text field ("What do you want to master?"). The on-device
   model generates the pack in validated steps, each using @Generable typed
   output:
   a. 5–8 cluster names for the career (+ one specialty lane)
   b. per cluster: 6–10 concepts with one-line quiz-usable definitions
   c. prerequisite arrows — then validate ON-DEVICE with plain code:
      DAG acyclicity, no dangling names, ≤8 prereqs per concept
   d. user reviews the generated map (rename/delete/add) before seeding
2. **Already know** — chips per cluster seed the first green dots.
3. **Theme** — palette picker (Ocean/Plum/Forest/Sunset/Mono) stored in
   AppStorage; `Theme` reads accent colors dynamically. Mastery semantics
   (dim → mid → known) constant across palettes; all palettes color-blind safe.
4. **Sources** — AI-suggested source names for the career + "paste any RSS/site
   URL" (validate by fetching one item; discover feeds via
   `<link rel="alternate" type="application/rss+xml">`).

**Fallbacks (no Apple Intelligence):** bundle 3–5 starter packs as JSON;
"Import pack" accepts the same JSON — users can generate one with any AI on
the web using §4 of this template and AirDrop it in. That JSON format doubles
as the marketplace pack format.

**Add to the data model:** `packSource` on Concept (`generated | imported |
expert`) so generated packs can show a "community/AI-generated — not
professional advice" banner (mandatory for medical/legal/financial careers),
and expert marketplace packs can replace generated ones cleanly.

**Privacy note:** the typed career + generated pack stay on-device like
everything else — a person's career ambitions are sensitive data too.

**Business note:** free tier = AI-generated pack; paid tier = expert-verified
packs + quiz/exam mode. Generation quality is the funnel, expert packs are
the product.
