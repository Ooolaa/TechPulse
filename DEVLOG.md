# TechPulse — Development Log

> Daily record of the development process. Newest first. Each entry: what was
> built, what was verified, and what was learned. Sibling project:
> [CareerPulse](../CareerPulse/DEVLOG.md) (the career-agnostic spin-off).

---

## 2026-07-19 — Concept-sheet navigation, chip contrast, Data Science sources, feed hardening

**Built**
- **Concept sheet became a navigation surface** (user request): the sheet now
  hosts its own NavigationStack — related-concept chips push the sibling
  concept's page ("tap to jump" across the map without leaving the sheet),
  article rows push the full ArticleView, and drilling in auto-expands the
  sheet to full height. Article list capped at 10 (was 4) with chevrons.
- **Second dark-mode contrast bug**, same shape as Settings: the selected
  feed category chip was `.white` text on `Theme.textPrimary` — white-on-white
  in dark mode. Fixed with the inverted-chip pattern (`Theme.card` text), now
  consistent with onboarding chips.
- **New sources, verified live before shipping** (curl: 200 + items):
  Kaggle Blog + KDnuggets under a new **Data Science** tag, TechCrunch — AI
  under Industry. Source seeding is now **incremental** (insert-by-URL), so
  app updates deliver new feeds to existing installs — previously seeding
  only ran on an empty table, meaning nobody updating would ever get them.
- **Feed fetch hardening** (template §6): https-only guard + 5 MB response
  cap on feed downloads (untrusted input; caps memory). Swift 6 gotcha again:
  the cap constant needed `nonisolated` to be readable from the task group.
- UI journey now drills the sheet deterministically via the frontier card
  (related-jump + article-row + close), so this UX has regression coverage.

**Verified** 21 unit tests + journeys green on the iPhone 17 sim in dark mode;
screenshots confirm readable selected chips, the Data Science tag populated
with KDnuggets/TechCrunch content on an *existing* data set (incremental
seeding), and the sheet jump: MLX → tap PyTorch chip → PyTorch page with back
button at full height. Installed on the iPhone 14 Pro.

**Follow-up (same day):** the Data Science tag arrived empty on the device —
three compounding causes, each now fixed:
1. Kaggle's Medium blog **died in 2020** — replaced with the live r/kaggle
   Atom feed and added a `retiredSourceURLs` mechanism that removes dead
   seeded sources from existing installs.
2. Reddit **403s default CFNetwork user-agents** — feed requests now send a
   descriptive `TechPulse/1.0` UA (plus a Reddit-style Atom fixture test:
   `t3_` ids, offset dates, html content — 22 unit tests now).
3. The daily 30-article cap was **already spent** before the update, so new
   sources starved until tomorrow — brand-new sources now bootstrap up to 5
   articles outside the cap (this also rescued DeepMind's quiet feed).
Also: **Data Science knowledge cluster** (8 concepts: EDA → features/CV →
GBT/ensembling → Kaggle Competitions, wired into Probability & Statistics),
`Class Imbalance` migrates from the resume seed into the new cluster, and
pack seeding is now **versioned** (`packVersion`) so existing installs merge
new pack content on update instead of being stranded by a one-shot flag.
Verified in the sim DB: r/kaggle = 5 fresh community posts after a forced
sync on an existing install.

**Also (same day): per-topic article discovery.** Topics the feeds never
cover ("Appears in 0 articles") can now pull content on demand:
`TopicSearchService` queries the arXiv API (Atom — the parser already speaks
it) for the newest papers matching the concept name and files them as
articles tagged to the concept, outside the daily cap (user-initiated, like
Go deeper). "Find fresh articles on arXiv" button shows in the concept sheet
whenever a topic has < 3 articles; separator-safe query builder
("LoRA / QLoRA" → quoted phrase) with 2 unit tests (24 total). Journey drills
it via the frontier card: MLX went 0 → 3 real papers in the screenshot.
Plus: Apple ML Research feed seeded (Research) — the authority source for the
On-Device AI cluster.

**Also (same day): Hot Topics radar.** The pack was strong on curriculum but
silent on the news cycle — no Vibe Coding, no Reasoning Models, no video
generation. Added a **Hot Topics cluster** (packVersion 3, 10 dots: Vision
Language Models [migrates from the resume seed, stays green], Reasoning
Models, Vibe Coding, World Models, Synthetic Data, Open-Weights Models,
Small Language Models, Diffusion Models, AI Video Generation, Humanoid
Robotics) wired into pack prerequisites, plus **Stage 8 · Staying current**
on the learning path. On the Feed, a **flame "Hot topics" chip** filters to
articles that either carry a Hot Topics concept or textually mention one
(alias list in KnowledgePack — works before analysis runs). Journey covers
the toggle; screenshot showed the filter surfacing AI-agent, robotics, and
agentic-AI stories from the live feed. 68 pack concepts total. (Swapped the
🔥 emoji for SF Symbol `flame.fill` — the sim rendered the emoji as a
placeholder box in chips.)

**Learned** An inverted chip (`textPrimary` bg + `.white` text) is a
dark-mode landmine — grep for the pattern after any theme change; two views
had it. Seed-only-when-empty silently strands existing installs: growth data
needs an upsert path, not an install-time path — the same lesson three ways
(sources, pack concepts, and the daily cap all needed an "existing install"
story). And check a feed's newest-item date before shipping it: a 200 with
items can still be a dead publication.

---

## 2026-07-17 — Adaptive dark mode, cluster-tree zoom affordances, graph perf, privacy-claim reconciliation

**Built**
- **Adaptive dark mode.** A device screenshot showed Settings half-broken in
  dark mode: system pieces (nav title, list rows) flipped dark while the
  hardcoded light tokens didn't — white "Settings" on a light background.
  Every `Theme` surface/text token is now adaptive via a `Color(light:dark:)`
  trait initializer; the three mastery state colors stay mode-constant on
  purpose (semantic vocabulary, color-blind-safe lightness order in both
  modes). All 41 stray view hexes were routed through new semantic tokens
  (ink scale, learning/known tint + border, track, danger, graph strokes),
  consolidating near-duplicate blues/greens along the way. The About footer's
  absolute "nothing leaves your iPhone" gained the BYO-key qualifier in-app.
- **Test-coverage gap closed**: the UI journey never screenshotted Settings —
  the one screen without capture was the one that shipped broken. The journey
  now snaps Settings top + scrolled footers. Also `GENERATE_INFOPLIST_FILE`
  for both test targets in `project.yml` (Xcode 26.3 stopped defaulting it).
- The cluster dependency tree ("what to learn next") already inherited
  `ForceGraphView`'s pinch-zoom, but silently — no "pinch to zoom" hint and,
  worse, no recenter, so a zoom/pan was a one-way trip until you left the screen.
  Added the hint to the legend and a top-right recenter button (same
  `.id(graphReset)` reset the full map uses).
- **Graph CPU fix** (from an on-device trace, below): `GraphSimulation.step()`
  was the #1 hotspot because the force sim never settled — a too-tight
  `maxSpeed < 0.05` threshold let sub-pixel jitter pin the O(n²) physics at 30fps
  forever. Added a hard 240-frame settle cap (net is visually done in ~3s, so no
  visible change) and cached the per-frame label-priority sort (rebuilt only on
  configure / frontier change).
- Reconciled the docs with the BYO-key reality: "no data leaves the device" is
  now "on-device by default, one opt-in exception" across README, Build-Spec §11,
  and Template §6 — only concept name/definition/cluster (never article text) goes
  to Anthropic, under the user's own key, so the "Data Not Collected" label still
  holds. Refreshed README milestones (was frozen at M6, missing four days of work).

**Verified** Full suite (21 unit + 2 UI journeys) green on the iPhone 17
simulator in **dark mode and again in light mode**; per-screen journey
screenshots reviewed in both — feed, article, cluster tree, full map,
progress, quiz, and the new Settings captures all legible. Rebuilt/reinstalled
on the physical iPhone 14 Pro (team H6V64XZ8VA); app launched on device. Real
10s on-device CPU trace (`xctrace record --template 'CPU Profiler'`) confirmed
`step()` as the top symbol pre-fix. Clean before/after still pending — needs
the app held on the graph screen for both traces.

**Learned** A feature can ship "working" yet read as broken purely for lack of an
affordance: the tree zoomed all along, but with no hint and no undo it felt like it
didn't. Docs are a shipping surface too — a privacy sentence copied into App Store
copy has to track the code, not the original intent. And a force-directed sim needs
an explicit stop condition, not just a settle threshold, or it burns battery idle.

---

## 2026-07-14 — BYO Claude key unlocks Go deeper (back-port from CareerPulse)

**Built** Added `KeychainStore` + `AnthropicClient` and wired the BYO-key path
into "Go deeper": on devices without Apple Intelligence (John's iPhone 14 Pro),
adding your own Claude API key in Settings → AI engine unlocks concept
expansion. Key lives in the Keychain only, used directly with Anthropic.
Also hardened the feed parser against XXE (external entities disabled) and
added an entitlements file.

**Verified** 21 unit + 2 UI journeys green.

---

## 2026-07-13 — Semantic zoom + readability round (`24209c1`, `ab409bc`)

**Built**
- Full-map labels are collision-culled (priority: frontier, then mastery) —
  no overlapping text at any zoom.
- Tap-a-dot **glossary strip** under the map: name, mastery chip, definition,
  "Details ›" — quick keyword review without leaving the map.
- **Full-text fetch**: articles that arrived as feed snippets now pull the
  real story from the publisher page (heuristic readability: `<article>`
  paragraphs), then regenerate the on-device summary from real text.
- **Semantic zoom** (user's design insight): zooming in spreads positions
  while dots/lines/labels keep constant screen size — overview may overlap,
  zoom always resolves it. Past 1.8× every dot gets a label. Max zoom 5×.
- Settings headers → heavy near-black; streak pill on Progress header.

**Verified** 21 unit tests (4 new extraction tests) + 2 UI journeys.
Simulator screenshots confirmed a decluttered map and a complete Verge
article fetched in-app.

**Learned** Swift 6 strict concurrency flags pure helpers inside `@MainActor`
enums — mark them `nonisolated`. Fresh installs made every dot "recent"
(all pulsing); recency must exclude the initial seeding batch.

---

## 2026-07-12 — Habit system, Lego-blocks UX, Go deeper (`6714005`, `4f1d173`, `b2bb783`)

**Built**
- **Atomic Habits reading system**: 30 fresh articles/day intake cap (newest
  across all feeds win), daily goal card (tiny default: 3; ring + streak +
  goal-met celebration + haptic), goal picker in Settings.
- Full map became a **cluster archipelago** (each topic an island with a
  faint label) replacing the hairball; "Full map — one net" entry card.
- Article **concept primer** ("know these before you read") with definitions;
  word-level selection via UITextView (SwiftUI selects whole blocks only);
  original-link storage + Safari/Share toolbar buttons; snippet footer for
  publishers that ship no body text (measured: HF/OpenAI = 0 chars,
  DeepMind ~117, Verge ~724, VentureBeat ~14k).
- **"Go deeper"**: on-device AI expands any concept into 3–5 linked
  sub-concepts on its island — the "pull" direction of learning. New dots
  ripple for 24h.
- First install on the physical iPhone 14 Pro (command-line signing:
  team H6V64XZ8VA + devicectl).

**Learned** RSS body length is a publisher choice, not a bug. iPhone 14 Pro
(A16) has no Apple Intelligence → fallback paths must be first-class; BYO
API key (CareerPulse U4) will unlock generation there.

---

## 2026-07-07 — Full build day: M1→M6 + Knowledge Pack + polish (16 commits)

**Built** (from spec `TechPulse-Build-Spec.md` in one continuous run)
- **M1** skeleton: SwiftData models, 4-tab navigation, seeded feeds, design tokens.
- **M2** feed pipeline: tolerant RSS/Atom/RDF parser, offline cache,
  article view, BackgroundTasks refresh.
- **M3** on-device intelligence: Foundation Models summaries + concept
  extraction with @Generable; NaturalLanguage fallback.
- **M4** knowledge engine: mastery scoring (read +0.1 / known 1.0 / quiz +0.3 /
  decay −0.05·mo), embedding dedupe, concept sheet with "I know this".
- **M5** force-directed knowledge graph (TimelineView + Canvas) + Swift Charts.
- **M6** quiz mode (question card → result with mastery deltas), resume-seeded
  green dots, Siri App Intent, onboarding, app icon, cache pruning,
  11→17 unit tests + XCUITest journey with screenshot capture.
- **Knowledge Pack**: ~50-concept AI-engineer skill tree with prerequisite
  arrows; cluster overview with GAP badge; frontier ("ready to learn") rings;
  "YOUR NEXT DOT" gap-detector feed; staged learning path.
- Polish: professional icon (3 design iterations), concurrent feed fetch,
  vocabulary-matching fallback (killed junk concepts), quiz distractors from
  the same cluster, unread badge, haptics.
- Wrote `CareerPulse-Template.md` — career-agnostic spec (+ §10 universal
  runtime-customization mode) that later became the CareerPulse project.

**Learned** SwiftData traps on repeated per-test ModelContainer creation
alongside the live app container (share one in-memory container per suite);
batch deletes violate inverse relationships (delete row-by-row); UI tests
catch real bugs code review misses (future-dated RSS timestamps, quiz chip
spoiling its own answer, junk "LiNO" recommendations).

---

*Repo: https://github.com/Ooolaa/TechPulse (private). Built with Claude Code.*
