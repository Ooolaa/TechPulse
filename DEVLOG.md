# TechPulse — Development Log

> Daily record of the development process. Newest first. Each entry: what was
> built, what was verified, and what was learned.
>
> Entries before 2026-08-17 refer to CareerPulse as an active sibling project.
> It is retired — one app, Packs are runtime data in it. See
> [ADR-0005](docs/adr/0005-careerpulse-is-retired-and-what-came-across.md) for
> what came across and what did not.

---

## 2026-08-17 — CareerPulse is retired, and the port is closed (#16)

**Built**
- **ADR-0005 accounts for CareerPulse file by file.** ADR-0001 decided the
  retirement two and a half weeks ago but never took the inventory, so "retired"
  and "abandoned mid-port" were indistinguishable from this repo. Taken against
  `af8ab0c` by comparing tracked files: thirteen existed only there, and each is
  now *brought across*, *tracked*, or *dropped* with a reason.
- **The security tests came across, and they were the thing that mattered.**
  `KeychainStore` and `AnthropicClient` were back-ported on 2026-07-14 **without
  their tests**, and the XXE hardening landed the same day the same way — three
  shipped security-relevant behaviours whose only coverage sat in the repo being
  retired, against this repo's own standing testing gate. Now
  `Tests/UnitTests/ByoKeyTests.swift` (Keychain round trip, Anthropic request
  shape, 401, and a 200 carrying no text block) plus one test in
  `RSSParserTests`.
- **`PRIVACY.md` was rewritten, not copied.** The original described a product
  that generates Packs, probes suggested feed URLs and shows a regulated-fields
  banner. This app does none of those, so those claims came out rather than
  being inherited, and what is left was checked line by line against the code —
  which is how the missing `TopicSearchService` cap turned into a filed issue
  rather than a sentence that was almost true.
- **ROADMAP Horizon 5 item 16 said the wrong thing** — it described exporting
  the Pack so two apps could coexist, the option ADR-0001 rejected. Rewritten,
  along with item 17 ("validate in CareerPulse first" — there is nowhere to
  validate but here now). The dropped theme palettes are pointed at from
  Horizon 4 item 12 so they are findable rather than lost.
- **Two issues filed for what the inventory turned up.** **#27**: `PackDraft`
  and `PackGenerator` were on ADR-0001's port list and never ported, with no
  ticket covering them — the one place the port was genuinely incomplete rather
  than deliberately narrowed. **#28**: `TopicSearchService` still has no
  response size cap, unlike both its siblings.

**Verified** 211 unit tests in 18 suites pass (206 + 5 new). The two ported
suites were **mutation-checked** rather than trusted for being green: removing
`SecItemUpdate` from the Keychain save path turns the round trip red, and
renaming the `x-api-key` header turns the request-shape test red. The Keychain
suite really does run here — the simulator's Keychain is reachable, so its
entitlement guard is not silently skipping the whole test.

**Learned** A test can be green from the day it is written and never have been
able to fail. The ported XXE test asserts that an entity payload yields no file
contents — but flipping `shouldResolveExternalEntities` to `true` leaves it
green, because a `Data`-backed `XMLParser` never fetches the external resource
either way (checked against an external-DTD payload too; the flag only gates the
declaration callback). Worse, it asserted only through `allSatisfy` over an array
that is empty for this input — vacuously true twice over. Kept as a regression
guard on the outcome, with the limit written down instead of implied, and an
`isEmpty` assertion that can actually fail.

The general shape: **a retirement is an inventory, not an announcement.** Every
item on the dropped list was easy to justify once written down, and impossible to
find while it wasn't.

---

## 2026-08-17 — Two halves that disagreed about case, and a crash loop from a file (#22)

**Built**
- **The validator now compares Concept names without case**, because the
  installer always resolved them that way. `PackValidator` rejected duplicates
  on the exact string, so a Pack declaring both `"RAG"` and `"rag"` passed;
  `PackInstaller` then resolved both onto one stored row (`byExactName` falling
  through to `byLowerName`), and wrote `conceptNames` naming that row twice.
  Two halves of the same rule, disagreeing — the file was valid by one and
  ambiguous by the other.
- **`topologicalOrder` tolerates a name it has already seen.** Both its indexes
  were built with `Dictionary(uniqueKeysWithValues:)`, which *traps* on a
  repeat. It is reached from `nextDot`, so the trap fired inside the importer
  and then on every launch that drew the next-dot banner: an unrecoverable
  crash loop, triggered by an imported file and surviving app restarts. Now
  both indexes keep the first mention and let the repeat collapse.

- **A stored record is now read as naming each Concept once**, at the point it
  is read rather than at the one call site that happened to crash.
  `/code-review` made the case: tolerating the repeat inside `topologicalOrder`
  fixed the trap and nothing else, so the same repeat still inflated the pack
  library's "N concepts" and the side-quest total, and `exportActivePack` still
  emitted it as two identical `PackConcept`s — a share file the *new* validator
  refuses to import. One `namedOnce` on the way out of the record fixes the
  ordering, the counts and the export together.
- **A rejection now names both spellings.** `duplicateConcept` carried only the
  second, so a file holding `RAG` and `rag` was reported as "two concepts named
  'rag'" — an author searches, finds one entry, and concludes the error is
  wrong. It carries both now, and words itself differently when the two are
  genuinely identical.

**Why both guards, when the first one closes the door.** The validator keeps the
bad file out from here on; it does nothing for a record already written to a
reader's store by a build that shipped without it. Those records are read at
every launch, so every path off one has to degrade rather than take the app
down — a recovery path, not a redundant check. The reproduction is exact: the
test crashed with `Fatal error: Duplicate values for key: 'rag'` before the fix.

**Note on what did *not* change.** Case-insensitive *resolution* is deliberate
and stays — a Concept the reader's own reading created as `rag` keeps its name,
its Mastery and its history when a Pack calls it `RAG`
(`installReusesCaseDifferingConcept`). The bug was never that resolution folds
case; it was that validation did not.

**Verified** 206 unit tests pass, including three new ones: a case-differing
duplicate is rejected naming both spellings, a record holding a name twice still
yields a path order, and such a record reports one Concept and exports a Pack
that re-validates. The review also checked that nothing legitimate is newly
rejected — no bundled pack, compiled `KnowledgePack` or test fixture contains a
case-differing pair.

`testCoreJourney` fails at "no cluster cards" — **pre-existing**, confirmed by
stashing this work and re-running on a clean tree at `b0f4157`. Filed as #26
with the diagnosis: the concept sheet is never dismissed, because `swipeDown` is
absorbed by the sheet's inner `ScrollView` and the journey ignores the
`closeSheet` button that exists for it. The screenshot proves it — the file
saved as `5-cluster-overview.png` is byte-identical to `3-concept-sheet.png`.
The deeper fault is that this journey alone runs against accumulated simulator
state, so what it asserts depends on what previous runs left behind.

**Learned** A validator and its consumer have to agree on what makes two things
the same thing. Where they disagree, the gap is not merely a bad message — it is
exactly the input that reaches code trusting a guarantee it never got. And the
first fix for such a gap is drawn too tight by default: I hardened the line that
crashed, when the untrusted value needed normalising at the point it is read.

---

## 2026-08-14 — Acting on the review: a Co-read Link now means what the glossary says

**Built**
- **Co-read Links come from articles you actually opened.** `rebuildCoreadLinks`
  had no `isRead` filter, so it wired the map from every *cached* article —
  and analysis attaches Concepts to all of them, read or not. `CONTEXT.md` has
  always said "Concepts you have met together in the same **reading**", and
  `isRead` is already the app's definition of reading: the same signal Mastery,
  Lit state and the Streak use. Only Co-read Links ignored it. #10 then put
  "Read together" on the map, which made the wrong semantics user-visible.
- **Not a regression — an inherited one.** The old `linkCooccurring` ran from
  `analyzePending`, which never looked at read state either. What changed is
  that #9 made the fix affordable: before Semantic Links, filtering to
  read-only would have left a new reader looking at dust. Now Semantic Links
  carry day one, so Co-read can afford to mean what it says.
- **The map on screen now redraws when edges change**, not when their *count*
  does. `rebuildCoreadLinks` deletes and reinserts the whole table, which
  routinely lands on the same count with different pairs — so a map open during
  a background analysis pass kept drawing stale edges. Keyed on a hash of the
  endpoints and strengths instead.

**Measured, rather than assumed.** The review also flagged the launch path as
blocking: `rebuildCoreadLinks` runs on the main actor in `TechPulseApp.init`
before the first frame. Measured across three store sizes, it costs **29ms at
300 cached / 100 read, and 44ms at 1200 / 500** — sub-linear, because the
`isRead` predicate filters in SQLite rather than in Swift. That does not justify
an async refactor, and deferring it would open a window where the engines read
an empty map at launch. Pinned with a budget test instead. The genuinely
expensive steps are both one-offs: installing a Pack, and the one upgrade
launch that backfills Semantic Links (~0.4s each).

**Learned** Three of the review's nine findings were in code from this session;
one of those (stale edges) was a real bug my tests could not have caught,
because every one of them called `configure` directly and never went through
SwiftUI's update path. Worth remembering that a unit-tested view model proves
nothing about when the view asks it for anything.

---

## 2026-08-13 — Three kinds of edge, and strength that moves the dots (#10)

**Built**
- **Each connection is drawn as its own kind of thing.** A Dependency is
  solid with an arrowhead, a Semantic Link is dashed and cooler, a Co-read
  Link is a plain line. Two cues each, not one — the dash and the arrow survive
  dark mode and colour blindness on their own, which colour alone would not.
- **Strength moves the dots.** The spring's rest length and stiffness now come
  from the edge, so strongly connected Concepts settle closer together.
  ADR-0002's complaint was that `weight` drove neither line width past 5 nor
  layout distance *at all*; a pair now settles between ~85pt and ~61pt across
  the strength range.
- **One line per pair.** A pair claimed by several kinds is drawn once, by the
  strongest claim — what someone asserted beats what you did, which beats what
  the words resemble. Two lines between the same two dots land exactly on top
  of each other and read as one thicker line, not as two facts.
- **The map has a key**, so the three kinds can be read rather than merely
  looked at, drawn from the same colours the Canvas uses.

**The bug the screenshots caught.** The first light/dark capture had no dashed
lines anywhere. Semantic Links are computed **at Pack install** — and the common
launch installs nothing, because the reader is already on the current Pack
version. So every store written before #9 would never receive them, and the map
would open as exactly the dust the feature existed to end. Only switching Packs
would have fixed it. `PackMigration.ensureSemanticLinks` backfills once, and a
test now reproduces the upgrade path directly. **This would have shipped**: the
unit suite was green, because every test installed a Pack first.

**Verified** 201 unit tests and all three UI journeys pass. Settling measured
before and after: both reach the same frame (238, just inside the existing
240-frame cap), so no regression. Journey captures the map in light and dark,
and at 3× zoom — at overview scale a 141-dot map is dense enough that any line
looks like any other, so a 1× screenshot would have proved nothing about
distinguishability.

**Learned** The second bad test of the day, same shape as #8's: `strengthMoves
TheDots` passed with the strength-driven spring reverted, because under the old
constant spring the two pairs settle **0.001pt** apart and `<` was a coin flip
on where the random start put them. Asserting a *meaningful* gap (>15pt) is what
makes it a test. Both times the mutation found it and the green suite did not.

---

## 2026-08-13 — Co-read Links stop being a hairball (#8)

**Built**
- **`CoreadScoring`** — pure, no store. Turns *readings* (groups of Concepts
  met together) into scored edges. Each of ADR-0002's three grievances against
  the old raw counter became one rule and one test:
  - every pair was linked → pairs form among a reading's **5 principal
    Concepts**, so an 8-Concept article emits 10 edges, not 28;
  - `weight` climbed forever unnormalised → strength is an **association**
    (Dice, tempered by how much reading is behind it), so a Concept that
    appears in everything scores near zero against each partner;
  - the weight was invisible anyway → strength keeps climbing instead of
    saturating at the old width formula's weight ≈ 4.4.
- **Mutual top-6**, the same shape #9 used, so no Concept keeps more than its
  strongest few and a hub can't reassemble itself out of other Concepts'
  shortlists.
- **Co-read Links became derived.** `KnowledgeEngine.rebuildCoreadLinks`
  recomputes the whole table from the reading record — `Article.concepts` plus
  the resume's projects — replacing incremental `linkCooccurring`.

**Why derived, and not just a better counter.** This was the load-bearing
decision. A counter that prunes itself cannot work: pruning a weak pair throws
away the very count that would later prove the pair mattered, so a pair read
together every few weeks would be pruned at weight 1 forever and could never
accumulate. Deriving from the reading record makes pruning free — the evidence
is the articles, which are untouched — so a pair that goes on being read
together earns its way back. It also gets AC 6 for nothing: a store written
before scoring existed is simply recomputed at launch.

**Verified** 189 unit tests pass (176 before). Mutation-tested all three
rules. The density test initially passed *with the group cap removed* — it was
asserting against the very constant it was meant to pin, and mutual top-K was
quietly masking it. Rewritten to assert the exact edge count (10) and that a
reading's trailing Concepts stay unlinked; it now fails at 21 edges without
the cap.

**Learned** A test that references the constant under test can't fail. The
mutation caught it; the green suite never would have. Worth checking any test
whose expected value is computed from production code rather than written out.

**Accepted regression** `IntelligenceService.deepen` no longer fabricates a
Co-read Link between a Concept and the sub-Concepts it generates. ADR-0002 is
explicit that a Co-read Link records what you actually read, and an invented
sub-concept is not that — the same call #4 made when it stopped mirroring
Dependencies. A deepened child now joins the map through the reading that
turns it up. Giving generated Concepts a proper derived edge belongs with #11
or #13.

---

## 2026-08-13 — Semantic Links: the map means something on day one (#9)

**Built**
- **`SemanticLink`, its own model.** ADR-0002's second edge kind, stored apart
  from `ConceptLink` (Co-read) and `ConceptDependency`. Separate rather than a
  flag on `ConceptLink` for one concrete reason: Semantic Links are *derived*
  and get rebuilt on every install, Co-read Links are a record of what the
  reader actually read and must never be thrown away. One table would make
  "recompute the derived ones" impossible to express safely.
- **`SemanticLinker`** — pure, on device, offline, no Apple Intelligence. Uses
  the `NLEmbedding` sentence embedding already present for Concept dedupe. The
  vector source is a parameter, so the graph rules are tested against
  coordinates a test chooses rather than against whatever Apple's model
  believes about AI jargon.
- **`PackInstaller.install` rebuilds the links** the same way it rebuilds
  Dependencies — the Pack owns its derived edges. Links are computed over the
  Concepts *as the store names them*, so an edge can never point at a name no
  fetch would find (the case-sensitivity trap #4 fell into).

**The measurement that changed the design.** The plan was a similarity
threshold. Probing the real Pack first killed it: raw cosine over 68 real
definitions gives a median pair of 0.47, same-Cluster pairs 0.52, and
"Sourdough Bread Baking" scores **0.46** against an AI Pack. There is no
threshold that both connects the map and excludes bread — generous (0.5) gave
909 links with one Concept joined to 53 others, ADR-0002's hairball; strict
(0.65) left 33 of 68 Concepts alone, ADR-0002's dust. Every English sentence is
a bit like every other, and that common component swamps the signal.

What works is judging relatedness two ways at once:
- **rank** on *centred* vectors (each Concept minus the Pack's mean meaning) —
  what makes this Concept distinctive, which ranks neighbours sensibly but has
  no absolute scale;
- **gate** on *raw* cosine, which does have a scale, so a foreign Concept is
  refused;
- **mutual top-5**, which is what actually delivers the readability criterion:
  no Concept can exceed 5 links, whatever the Pack looks like.

Result on the flagship: 119 links, nothing isolated, one connected component,
and all three foreign Concepts left unlinked.

**Verified** 176 unit tests pass (155 before). Both new guards were
mutation-tested rather than trusted: dropping the floor to 0.0 linked all three
outsiders and broke 3 tests; ranking on raw instead of centred vectors
fractured the flagship into 14 islands with 11 isolated dots. `vDSP` over
pre-normalised vectors made the similarity pass 130× faster than the scalar
version (0.86 ms vs 112 ms at N=68), which left the per-Concept embedding call
(~6 ms) as the entire cost: ~0.4 s for the flagship, once per install.

**Learned** Measuring the embedding *before* designing around it was the whole
ticket. The ticket, the ADR and my own first instinct all said "threshold"; 20
minutes of probing showed a threshold cannot satisfy two of the acceptance
criteria simultaneously, and pointed at the fix. Also worth knowing: the CI
simulator has no Apple Intelligence at all (`modelcatalog` errors in every run),
which makes it accidental but genuine proof of the "works without Apple
Intelligence" criterion.

**Not in this ticket** Nothing *draws* these links yet — `FullMapView` and
`ForceGraphView` still query `ConceptLink` only. Rendering three distinguishable
edge kinds with strength driving layout is #10, which ADR-0002 sequences after
this.

---

## 2026-07-31 — Agent skills configured; the tracker gets a vocabulary

**Built**
- **`docs/agents/`** — the config the engineering skills assume, previously
  absent. `issue-tracker.md` (GitHub issues via the `gh` CLI, with the
  wayfinder map/sub-issue/dependency conventions), `triage-labels.md`, and
  `domain.md`. A new root **`CLAUDE.md`** points at all three.
- **The triage vocabulary now exists as real labels.** `needs-triage`,
  `needs-info`, `ready-for-agent`, `ready-for-human` created on the repo;
  GitHub's stock `wontfix` reused as-is. This was the gap that mattered:
  `gh issue edit --add-label` *errors* on a label that doesn't exist, so
  `/triage` would have failed on its first run against a repo that, until
  today, had never had a single issue filed.
- **Single-context domain layout** recorded — `CONTEXT.md` + `docs/adr/` at the
  root. Neither exists yet, and that's deliberate: `/domain-modeling` creates
  them lazily when a term or decision actually needs pinning down.
- **Deliberately not committed.** These files sit in the working tree
  alongside the in-flight dark-mode/widgets/Explain work rather than landing
  as a tooling commit in PR #1's diff.

**Verified** `gh label list` returns all five canonical roles with the intended
colours and descriptions. The four config files are byte-identical to
CareerPulse's, so the hand re-sync between the repos can't skew them.

**Learned** The setup skill's defaults assume a repo that has *used* its issue
tracker. This one never had — issues enabled, zero filed — so the label
vocabulary the docs described was pure fiction until it was actually created.
Writing config that names things which don't exist is the failure mode to watch
for: it reads as done and breaks on first use.

---

## 2026-07-30 — "Explain" on word selection

**Built**
- **Explain on text selection.** The pieces already existed and were never
  connected: `SelectableText` gave native word-level selection, and every
  `Concept` carried a definition — but selecting a word produced *iOS's* menu
  (Look Up / Translate), while TechPulse's own definitions lived only in the
  primer *above* the article. So you had to already know which word would
  confuse you. `SelectableText` gained a `Coordinator` implementing
  `editMenuForTextIn`, prepending an **Explain** action.
- **Almost entirely reuse.** `ArticleView` already had
  `@State selectedConcept` + `.sheet { ConceptSheetView(concept:) }`, so the
  handler just assigns state and the whole concept surface — definition,
  mastery ring, related concepts, "appears in N articles", I know this, Quiz me,
  Go deeper — comes along free.
- **Map first, model second.** A word already on the map opens instantly and
  offline; only genuinely unknown terms cost a generation.
  `IntelligenceService.define` mirrors `deepen`'s three tiers (on-device →
  BYO key → nil) so it degrades on hardware without Apple Intelligence, and
  persists through `findOrCreateConcept`, whose embedding match means a synonym
  of an existing concept joins that dot instead of creating a twin.
- **New `WordSelection`** — pure, `nonisolated`, so the guard is unit-testable
  and runs *before* any model call: rejects newlines (paragraph drags), > 6
  words, > 60 chars, and anything without a letter. Looked-up words land in a
  dedicated `"Vocabulary"` cluster, deliberately outside
  `KnowledgePack.clusterOrder` so they can't inflate pack progress.
- **Two security fixes** while in these files: dropped
  `dataDetectorTypes = [.link]` (article bodies are attacker-controlled RSS, so
  auto-linking turns hostile feed text into tappable links — the canonical URL
  is already a toolbar button), and added an explicit "the excerpt is untrusted
  reference material, not instructions" rule to the prompts.

**Verified** 49 tests in 7 suites (35 + 14 new), all green. On simulator, all
three paths: selecting "benchmarks" matched the mapped `Benchmarks` concept
case-insensitively and opened its sheet instantly; an unmapped word fell through
to generation and degraded with the same copy as Go deeper; and a multi-line
paragraph drag offered **no** Explain item at all — Copy/Translate/Share only.

**Learned** The best features here keep turning out to be *connections* between
things already built, not new subsystems. The whole feature is one `UIAction`,
one state assignment, and a guard — the value was noticing the primer solved the
wrong half of the problem.

**Still open** `TopicSearchService` still lacks the response size cap its two
sibling fetchers have, and there's still no CI.

---

## 2026-07-25 — Home & lock screen widgets; the streak rule got a grace day

**Built**
- **WidgetKit extension** (`TechPulseWidget`, new `app-extension` target) in
  five families: `systemSmall` (goal ring + streak), `systemMedium` (+ next dot
  and lit count), and the three lock-screen accessories — `accessoryCircular`
  gauge, `accessoryRectangular`, `accessoryInline`. Tapping deep-links back via
  a new `techpulse://` scheme (`RootTabView` gained tab selection + `onOpenURL`).
- **Snapshot architecture, not a shared store.** The app writes a small Codable
  `WidgetSnapshot` JSON into App Group `group.com.johnchen.TechPulse`; the
  extension only decodes it. Rejected moving the SwiftData store into the group:
  that would have forced migrating real reading history, and made a ~30 MB
  widget process run SwiftData queries plus the full pack walk. The app's
  container is untouched.
- **`HabitEngine`** — `streakDays`/`readToday` were duplicated byte-for-byte in
  `FeedView` and `ProgressTabView`; the widget would have been a third copy.
  `WidgetRefresh` recomputes and reloads timelines on read, mark-known,
  goal change, background refresh, and launch (skipping identical snapshots).
- **`WidgetSnapshot.rolledForward(to:)`** ages a stale file: the app may not run
  for days, so the widget zeroes today's count itself at the midnight entry.

**Verified** 35 tests in 6 suites (24 existing + 11 new, all green). On the
simulator, end-to-end: App Group container resolves, snapshot matched the app
exactly (40/89 lit, next dot "Linear Algebra"), reading an article moved the
widget 1/3 → 2/3 live, deep link opened the Knowledge tab, and all five families
render in light and dark.

**Learned** A widget is a forcing function for habit-rule bugs. `streakDays`
returned 0 unless you'd read *that day* — invisible in-app (you only see it
after opening) but a home-screen widget would announce "0-day streak" every
morning on a 30-day run. Streaks now survive one unextended day. Also:
`-Simulated.xcent` is where simulator entitlements actually live; the entitlements
baked into the binary read empty and look alarming but aren't.

**Deferred** Live Activity, deliberately — a streak isn't a time-bound event.
Reasoning and the reading-session alternative recorded in ROADMAP.md item 5.

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
