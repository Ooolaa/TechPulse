# TechPulse — Development Log

> Daily record of the development process. Newest first. Each entry: what was
> built, what was verified, and what was learned.
>
> Entries before 2026-08-17 refer to CareerPulse as an active sibling project.
> It is retired — one app, Packs are runtime data in it. See
> [ADR-0005](docs/adr/0005-careerpulse-is-retired-and-what-came-across.md) for
> what came across and what did not.

---

## 2026-08-19 — Analysis waited on the network, so the planted Article lost its Concepts (#33 follow-up)

**Built**
- **The journeys were failing on this machine, and the on-device model was not
  why.** `testCoreJourney` timed out waiting for a Concept chip on the planted
  Article, and the simulator's missing model catalog was the obvious suspect —
  the log is full of it. It was the wrong suspect: `IntelligenceService` already
  falls back to matching the Pack's vocabulary when the model does not answer,
  and a store-level test proves it attaches Concepts to that exact Article in
  half a second with no model at all.
- **`FeedView.task` synced before it analyzed.** So nothing already in the store
  got looked at until a network round trip finished, and when it did finish,
  `analyzePending` takes the newest eight — thirty articles the sync had just
  brought in, against one planted moments earlier. The planted Article could
  lose that race outright, which is the state-dependence #30 set out to remove,
  wearing a different hat.
- **Analyze first, then sync.** Local work does not wait on the network, and an
  article that arrived before this launch does not compete with a batch that
  arrived during it. `sync()` still analyzes what it brings in, so the trailing
  catch-up call went away. A reader opening a cached article now sees its
  Concepts without waiting on a sync — the same fix, on the user-facing side.

**Verified** All four UI journeys pass, 191.8s against #30's 187.5s baseline —
`testCoreJourney` 114.1s, and `5b4-related-concept-jump` runs as a required step
rather than being asserted and hoped for. 297 unit tests, 3 new: the planted
Article's text names Pack Concepts, analysis attaches them with no model
available, and reading it leaves Co-read Links behind. Those three take 1.7s and
cover the premise the journey spends three minutes reaching, so the next time it
breaks the log will say whether the app or the UI is at fault.

**Learned** The failing environment was loud about one thing — a missing model
catalog, printed hundreds of times — and the actual defect was silent and
elsewhere. Reaching for the loud explanation would have left a real ordering bug
in the app and a journey step marked required on faith. What settled it was
cheap: reproduce the journey's premise at store level, where a wrong answer
arrives in a second instead of three minutes.

---

## 2026-08-19 — The map drew the connection; the sheet, where you follow it, did not (#33)

**Built**
- **The sheet read one edge kind out of three.** `ConceptSheetView.relatedConcepts`
  came from `@Query var allLinks: [ConceptLink]` and nothing else, so "Related
  concepts — tap to jump" rendered only for a Concept your reading had already
  joined to another. `FullMapView` has queried `SemanticLink` since ADR-0002 and
  draws it as the "Related" edge. So the map showed a fresh install joined up,
  you tapped a dot, and the sheet said nothing about the neighbours you had just
  seen — ADR-0002's day-one failure surviving in the one surface a reader uses
  to act on it.
- **`ConceptNeighbours` answers the sheet's actual question**: given this
  Concept, what can I offer as a jump, and on what grounds. It reads both
  undirected kinds through one `UndirectedConceptEdge` protocol, drops a link
  whose other end this store has no Concept for, and takes the strongest link of
  a repeated pair. The sheet keeps a computed property and a render; the rule is
  testable without a view.
- **The two claims stay apart.** "Read together" is a record of your reading;
  "Related in meaning" was computed from the Pack's definitions at install.
  ADR-0002 stores and draws them differently, and the sheet now says which is
  which — the map's legend says "Read together" and "Related", and inside a
  section already headed "Related concepts" the second needs its extra word to
  say anything. A pair that earned both kinds is claimed once, by the reading:
  the stronger claim, and the same chip twice under two headings would be a lie
  about one of them.
- **Six chips, and the row fills.** Half is reserved for whichever kind has
  fewer to show and only for as many as it actually has, so one Co-read
  neighbour and six Semantic ones is 1 + 5 rather than four chips and a gap.
  Neither kind can crowd the other out; neither leaves the row short.
- **`5b4-related-concept-jump` is a required step now.** It was the last
  declared exception #30 left, and its reason was this defect. Both drill-
  throughs now name the heading they rely on and assert it, because one chip
  identifier serves both rows — without that, a sheet offering only the other
  kind would pass while the failure message blamed the wrong edge.

**Verified** 294 unit tests, 12 new. The rule's tests are pure, but a pure rule
cannot say whether a real install leaves anything to jump to, so the one that
carries the ticket installs the flagship Pack with the embedding the app ships
with — no injected vectors — and asserts that every one of the six frontier
Concepts has Semantic-Link neighbours and no Co-read ones. Mutation-checked:
make the rule ignore Semantic Links and it goes red six times, once per frontier
Concept.

**Correction (2026-08-19):** this entry first said the UI journeys could not run
here and that `5b4` was required on the strength of the install test alone,
because `testCoreJourney` failed at `openSeededArticle` and failed identically
on a clean tree at `a06e069`. The pre-existing failure was real; blaming the
simulator's missing on-device model for it was wrong. The cause was analysis
ordering, fixed in the entry above, and the four journeys now pass — `5b4`
included. The install test still stands, and still proves the data premise
rather than the render.

**Learned** ADR-0002 was implemented in the renderer and not in the reader. The
Semantic Links existed, were correct, and were drawn — and the feature they were
computed for still didn't work, because the surface that acts on a connection
queried the other table. Worth asking of any new edge kind: every place the old
one is read, not just the place it is drawn.

---

## 2026-08-19 — The widget aged a streak forward on a grace day already spent (#25)

**Built**
- **The widget ages its own file forward, and it aged one day too generously.**
  `WidgetSnapshot.rolledForward(to:)` dropped the streak to zero once two days
  had elapsed since the file was written, mirroring the one grace day
  `HabitEngine.streakDays` allows. The mirror is only right when the file's own
  day was read. A snapshot carrying `readToday == 0` already means "last read
  was yesterday" — the grace is spent in the file itself — so a second day's
  worth of it showed a live N-day streak, and the "read one article to keep it
  alive" prompt with it, on a morning the streak rule calls broken.
- **How much grace is left is a property of the snapshot, not a constant.**
  `readToday > 0` leaves one further day; `readToday == 0` leaves none. That is
  the whole fix — the file already carried what distinguishes the two cases, so
  no new field and no format change (the widget reads this JSON out of the App
  Group; adding to it is not free).
- **`streakAtRisk` and `isEmpty` are derived, and came right on their own** once
  the aged streak did. The widget cannot now prompt you to save a streak that
  has already ended.

**Verified** 282 unit tests green, 4 new. The one that matters pairs
`rolledForward(to:)` against `HabitEngine.streakDays(articles:now:)` over the
same reading history across four viewing days, for a streak written on an
unextended day and one written on an extended day — the ageing rule is an
approximation of the engine, so the test asserts the two agree rather than
restating the arithmetic. Before the fix it fails exactly where #25 says: one
day after an unextended snapshot, 5 against the engine's 0. The existing
roll-forward tests (same day untouched, next day keeps the streak, two days
breaks it) assert the same things and still pass — that path was never wrong.
They and the new ones now build their snapshot through one helper, so each test
reads as the single value it varies.

**Learned** The bug was a rule copied into a second place where its input had a
different meaning. `elapsed >= 2` was a correct reading of the grace day, then
was applied to a snapshot that had already consumed one. Where a cheap
approximation shadows an authority, the useful test is not "does the
approximation return what I expect" but "does it return what the authority
returns" — the same history through both, at several times. That test would
have caught this the day the roll-forward was written.

---

## 2026-08-19 — The row that said which Pack you were on had no second copy (#37)

**Built**
- **Losing the record meant losing the Pack.** `PackMigration` read which Pack
  the reader was on from one place — the `InstalledPack` row — and treated its
  absence as "fresh install, or a store from before Packs were data". Both of
  those want the flagship installed over the top, so that is what a store which
  had simply *lost* the row got: a Security Engineering reader came back on AI
  Engineering, and a reader on a Pack they imported came back on AI Engineering
  with `PackInstaller` rebuilding `ConceptDependency` from the flagship on the
  way, taking their edges too. #21 closed the way in; this is the hole it lit up.
- **`ActivePackIdentity` keeps the answer where a store migration cannot reach
  it.** Two strings in `UserDefaults` — the Pack's field and its origin —
  written by every install, and by the ordinary launch too, so a reader who
  upgrades into this build and installs nothing still ends up with a memory.
  The record is still the Pack; this is only its name.
- **Launch now tells the cases apart.** Nothing remembered still means the
  flagship, which is right for a fresh store and for a pre-Packs one. A record
  that is merely *inactive* is reactivated rather than rebuilt — nothing was
  lost, and rebuilding would throw away Stages and Sources it still has. A
  remembered built-in is reinstalled by field, so it comes back whole; a
  remembered built-in that no longer ships falls back to the flagship rather
  than minting a record claiming to be a built-in no build has, which the
  version bump — which finds built-ins *by field* — could never repair.
- **A Pack the reader brought has no file to reinstall from, so the map is read
  back instead.** `PackInstaller.adoptSurvivingMap` rebuilds the record out of
  what outlived it, and the membership question has an exact answer: Semantic
  Links are written in exactly one place, over a Pack's own Concepts, so the
  edges that survived name the Pack and a Concept the reader's own reading
  discovered has none. That matters beyond tidiness — ADR-0001 keeps non-Pack
  Concepts out of the Frontier because a Concept with no Dependencies is
  trivially ready, so a recovered Pack that swept up everything would put a
  word from yesterday's article forward as the Next Dot.
- **What comes back is still narrower, and says so.** No Stages — ADR-0004
  already derives a reading order from Dependencies, so the path still means
  something. No specialty Cluster, so no Side Quest lane. No author-suggested
  Sources; the reader's own subscriptions are `FeedSource` rows and were never
  in question. And a Pack whose Semantic Links never computed has none to read
  back, so there the whole map is adopted — the best answer available, with the
  Frontier cost named in the comment.
- **Stores damaged before this ships have nothing to remember with.** They keep
  today's behaviour and land on the flagship. The app is not on the App Store,
  so that population is dev devices — accepted rather than worked around.

**Verified** 278 unit tests green, 7 new, all at the launch seam
(`ensureBuiltinInstalled`) the existing suite already tests through, plus the
four UI journeys re-run because this changes what happens on launch. Delete the
`InstalledPack` row from a Security Engineering store and the reader comes back
on Security Engineering with its six Stages, its Mastery and its history — that
path reinstalls over the top, so it is the one where what was learned could
plausibly be lost. Do it to an imported "Product Design" store and the two
Concepts, their two Clusters in order and their single Dependency are all there
under the right name, with a Concept the reader picked up from an article left
on the map but out of the Pack. Disable the branch and the recovery tests go red
in the shape #37 describes — 68 flagship Concepts poured over a two-Concept map.

**Learned** "No record" was several situations wearing one face, and the code
could only see two of them because the others had never happened yet. The fix
was not smarter inference from the store — the store cannot say whose map it is
— but a second, cheaper copy of the one fact that mattered, kept where the
failure could not reach it. Then the review found the fact I *could* infer:
Semantic Links have exactly one writer, so they were already a record of Pack
membership, sitting in the store the whole time. Worth asking of any single row
the app cannot recompute: what reads it, and what happens the day it is gone.

---

## 2026-08-19 — Siri's weekly question opened the store with a schema that deleted your Packs (#21)

**Built**
- **`WeeklyLearningIntent` opened the app's own store with a schema missing
  `InstalledPack`.** The list of models was hand-written at the call site, and
  the Pack work added a model to the app's list and to `PreviewData`'s but not
  to this one.
- **The ticket predicted a throw. It is worse than that.** A `ModelContainer`
  opened with *fewer* models than the store holds does not refuse to open it:
  SwiftData migrates the store down to the schema it was handed and drops the
  tables that schema doesn't name. So asking Siri "what did I learn this week?"
  deleted the reader's installed Packs — the Active Pack, its Stages, its
  authored Concept list — and the app came back next launch to a store with no
  Pack in it. The generic Siri error the ticket describes never appeared,
  which is why nothing caught this: the intent answered fine, and the damage
  showed up somewhere else entirely.
- **`AppSchema` declares the models once.** Two doors, both onto the same
  schema: `container()` for the reader's store on disk, `inMemoryContainer()`
  for the previews and the ten test suites that had each been writing out the
  model list *and* the in-memory flag by hand. Adding a model is one edit, and
  there is no list left to remember.
- **Stores already damaged are not repaired here.** A reader who asked Siri on a
  build before this one lost the `InstalledPack` row, not their reading:
  `Concept`, `LearningEvent` and the Links were all in the intent's schema and
  survived. `PackMigration.ensureBuiltinInstalled` puts a builtin reader back on
  the flagship Pack at next launch, but a reader on an imported or generated
  Pack comes back on AI Engineer with their Mastery intact and their Pack gone.
  That is #37, fixed the same day in the entry above.
- **`conceptsAdvanced(inWeekBefore:context:)` and `spokenAnswer(for:)` came out
  of `perform`.** The week window, the "Mastery actually moved" filter and the
  sentence itself are the parts worth testing, and `perform`'s own return is an
  opaque `some IntentResult & ProvidesDialog` a test cannot read — so a test
  that only calls `perform` cannot tell a right answer from a wrong one.
  `perform` is now the store, those two calls and nothing else. The window
  itself is untouched — naming it invited an upper bound (a week ending now
  does not contain tomorrow, and a future-dated Source timestamp has reached
  this store before), and that is a question about the week rather than about
  the schema, so it stays as it was and says so in a comment.

**Verified** 271 unit tests green, 6 new. The one that counts writes an
`InstalledPack` into the store the app itself created — the unit bundle's test
host *is* the app, so this is the real on-disk store, not a fixture — asks the
intent its question, reopens the store and requires the Pack still to be there.
Put the old hand-written schema back in the intent and it goes red, with
SwiftData logging the truncation on the way past; the first version of that
test, which only asserted `perform` didn't throw, passed against the bug. The
rest pin the week window (an event 30 days old and one that moved no Mastery
are both left out) and the three sentences Siri can say. Two suites that had been
quietly building containers without `InstalledPack` now build the app's schema
and stayed green.

**Learned** "Incompatible schema" was the wrong mental model, and it made the
first test useless. A narrower schema is not rejected, it is *applied* — the
mismatch is resolved by deleting the difference. So the test for a drifted
schema can't be "does it open"; it has to be "is the data still there
afterwards". And the reason the drift lasted: a list of every model, written
out at each call site, reads as configuration at all three, so nothing about
the third one looked incomplete.

---

## 2026-08-18 — One cap, named once, and a test that drives the fetch (#28)

**Built**
- **`TopicSearchService` had no size cap at all.** Its two siblings each had
  one — `FeedSyncService` behind a named `maxFeedBytes`, `FullTextService` as a
  bare `5_000_000` — and the topic search took whatever `URLSession` returned
  and handed it to `RSSParser`. Its URL is built from a Concept name rather than
  from a Source the reader enabled, so the bytes are no more trustworthy than a
  feed's.
- **`ResponseLimit` asks the two questions once.** Did it come back OK, and is it
  a plausible size. All three fetchers now go through it, so `PRIVACY.md`'s
  sentence is true of the app rather than of the two fetchers that happened to
  carry a copy of the number.
- **One byte changed hands.** `FeedSyncService` used `<=` and `FullTextService`
  `<`, against a documented promise that responses *over* 5 MB are discarded.
  `<=` is the promise, so a page of exactly 5,000,000 bytes is now read where it
  used to be dropped. Small, deliberate, and a test pins it.
- **`PRIVACY.md` no longer needs its qualifier.** The bullet read "Feed and
  article responses" — narrowed at some point to stay true of the code, which is
  the quieter half of the failure #32 was about: a document bent to fit rather
  than overclaiming. It now says every response the app fetches.
- **Which turned out to be four fetchers, not three.** Widening the sentence made
  it false again immediately: `AnthropicClient` fetches from `api.anthropic.com`
  and decodes the reply with no size check. It now refuses an over-cap reply
  *before* the status check, because the error path renders the body into a
  message — an over-cap reply must not be worked on in order to be complained
  about. It shares the number rather than the predicate: `accepts` folds in a
  status test this call site answers for itself, in 401-specific language the
  reader needs.

**Verified** 260 unit tests green, 9 new. The one that counts drives
`findArticles` over a stubbed 5 MB arXiv response and asserts no Article is
filed — with a control that runs the *same* feed under the cap and asserts one
is, so the refusal is the cap and not a stub that never intercepted. Removing
the cap turns four assertions red, including `tagged == 0` becoming `tagged == 1`
with an Article in the store: the over-cap body really is parsed without it. The
Anthropic path has the same pair, through the session `ByoKeyTests` already
injects.

**Learned** Widening a claim is where you find out how many places it has to be
true of. The grep that closed #32 asked which documents said a thing; the grep
that closed this one asked which *call sites* had to earn it, and the honest
answer was one more than the ticket named. Both reviews found the fourth fetcher
independently — the Spec axis by grepping `URLSession` against the new sentence,
which is the check the sentence now deserves every time it is restated.

Also: the transport seam this needed does not exist in production, and did not
need to. `URLProtocol.registerClass` intercepts `URLSession.shared` itself,
scoped by `canInit` to one host, so the test drives the real code path with
nothing in the app that exists only for tests.

---

## 2026-08-18 — "No article text" was an absolute, and the word you select is article text (#32)

**Built** (prose only — no behaviour changed; the three Swift edits are doc
comments)
- **ADR-0006's decision sentence is corrected, and says what it used to say.**
  It read "the opt-in path sends the selected term, the Active Pack's field, and
  its Cluster names. **No article text.**" The second sentence contradicts the
  first: the selected term *is* article text, a fragment of an RSS body bounded
  by `WordSelection.normalize` to six words and sixty characters. It now reads
  "No *passage* of the article", with a dated `**Correction (2026-08-18):**`
  paragraph under it quoting the original. Both halves are the point — quoting
  keeps the record of what was restated elsewhere while it stood, fixing removes
  the sentence that would be restated next.
- **The absolute was in three places, not one.** `PRIVACY.md`'s Explain bullet
  carried it too, and contradicted *itself* five lines later ("the word itself is
  article text, and it is the only article text there is"). Its Go deeper bullet
  carried it as well — and there it is not quite true either: a Concept's name
  may be a word the on-device analysis lifted from something you read. Both
  bullets now make the passage claim, and the Go deeper one says the quiet part.
- **`CONTEXT.md`'s `Egress` entry now carries the shared phrasing**, so the term
  defines the sentence every other document has to match: *no passage of what you
  are reading leaves, and a word you select is the most of an article that ever
  does*. `README.md` and `ROADMAP.md` already said exactly that — #29's review
  caught them before they landed. The ADR that generated them was the one still
  carrying the absolute.
- **The code said it too.** `ExplainPrompt`'s type comment and its `optIn`
  builder, and `IntelligenceService.define`'s comment, all carried "no article
  text" — the absolute restated inside the very files written to make the claim
  checkable. All three now make the passage claim. The grep is the check the
  documents could not do for themselves.
- **The convention for correcting a landed ADR is written down** in
  `docs/agents/domain.md`, since this is the second correction ADR-0006 has taken
  and the first time the *form* mattered: supersede when the decision changes,
  correct in place with a dated note when the decision stands and a sentence was
  wrong, amend a consequence in place when it turned out narrower than claimed
  (#31 was that third case). It also says a correction touching `Egress` changes
  five documents together, and to grep the old wording across Markdown *and*
  Swift — because doc comments restate these claims too, which is how three of
  them kept this one alive.

**Verified** 251 unit tests green, unchanged — no Swift behaviour was touched.
The check that mattered was a grep across Markdown *and* Swift: `no article text`
no longer appears as a live claim in either. What remains is the correction note
quoting the retired sentence, and dated DEVLOG entries — including the #29 one
three entries below, which already recorded *"'No article text' was not true: the
word you select is article text"* while the ADR that wrote the phrase went on
saying it.

**Learned** Both corrections ADR-0006 has needed were absolutes that were nearly
true — "never reach a model at all" (#31) and "No article text" (#32) — and both
were written by the document whose own diagnosis is *a claim with an exception is
a claim somebody will restate without the exception*. Knowing the failure mode
does not stop you writing it; the bounded sentence has to be the habit. Saying
what **is** sent, and what is the most that ever leaves, survives restatement in
a way that any "no X" does not.

---

## 2026-08-18 — Explain matches the map on spelling, not on meaning (#31)

**Built**
- **ADR-0007, because the sentence was load-bearing.** ADR-0006 accepted a
  quality cost — a word ambiguous inside your own field is no longer separable
  once the excerpt stops being sent — on the grounds that such words are
  "disproportionately words already on the map, which never reach a model at
  all". `ArticleView.explain` matched a Concept by name, case-insensitively and
  nothing else, so **"LoRAs", "low-rank-adaptation" and "RAG systems" each fell
  through to a generation**: on the opt-in path, one more selected word leaving
  the device. A consequence accepted on a mitigation is only as accepted as the
  mitigation is true, so this is an ADR rather than a patch.
- **`ConceptMatch` folds spelling — case, separators, English plurals — and
  stops.** "LoRAs" finds `LoRA`; "low-rank-adaptation" finds `Low-Rank
  Adaptation`. An exactly-spelled name still beats one that merely folds the
  same, so the fold only widens what matches: nothing that opened a Concept
  before opens a different one now. Synonyms and phrases ("RAG systems") still reach a
  model, stated as a test rather than left as an oversight.
- **The rejected option was the more capable one.** Moving the embedding match
  ahead of generating would catch synonyms too — and would put an `NLEmbedding`
  pass on every selection, and would reuse a 0.25 distance threshold chosen for
  *deduping a result the model already returned* to decide *not to ask at all*.
  A false positive there hands the reader a definition of a Concept they did not
  tap, offline, with nothing to signal the substitution.
- **The call site is the claim, so the call site is tested.** `ExplainRoute`
  lifts the decision out of the view: map first, model second, with `canDeepen`
  asked *after* the map, so a word you already have is explained on hardware
  that can explain nothing. #29's own review had found tested builders behind an
  untested call site (`1f8334e`); this is the same shape, caught before shipping.

**Verified** 251 unit tests green, 12 of them new — 8 in `ConceptMatchTests`,
4 in `ExplainRouteTests`. The `-es` rule went red first on a real case, not a
hypothetical: a stem test of a single "s" took "databases" to "databas" and lost
`Vector Database`. It now strips "es" only after stems that cannot take a bare
"s" ("ss", "x", "z", "sh", "ch"), so "losses" → "loss" and "databases" →
"database". Both halves mutation-checked: neutering `singular` to return its
word unchanged turns five assertions red, and dropping the exact-match
preference from `first` turns the tie-break test red on its own.

**Learned** Over-folding and over-matching fail differently, and that asymmetry
is the whole design. The fold runs on *both* sides of the comparison, so folding
too hard produces a wrong answer only where two Concept names fold together — a
map that would already confuse its reader — while an embedding threshold is
one-sided and fails silently, in the direction of showing a definition nobody
asked for. A rough plural rule is acceptable where a similarity score is not.

---

## 2026-08-18 — A skipped step is now a failure, not a green run (#30)

**Built**
- **Every journey declares its steps, and a step that does not run fails.**
  `JourneyLedger` and `ScreenshotEvidence` (`Tests/Support/`) are the
  bookkeeping: a journey lists its steps up front, `snap()` records one and
  writes its PNG, and `finish()` names every declared step that never ran, every
  step that ran without being declared, and every screenshot that is not from
  this run. `Journey` (`Tests/UITests/`) wraps that around `XCUIApplication`.
- **The bookkeeping has its own tests, in the *unit* bundle.** `Tests/Support` is
  compiled into both test targets, so the 13 tests that cover "a required step
  that never ran is named" and "a file left over from an earlier run is not
  evidence" run in 0.02s instead of three minutes. Both were mutation-checked —
  with `missing` stubbed to `[]` and the staleness comparison forced false, five
  and one of them go red respectively.
- **Screenshots are checked like evidence.** Each journey deletes its own PNGs
  before it starts and asserts, on writing and again at the end, that the file
  exists, is non-empty and post-dates the run. #26 was cracked by noticing that
  `4-marked-known.png` was four days old — by comparing file timestamps by hand.
- **15 `if element.exists` branches became assertions; three are declared
  optional and say why.** Only one of the three is skipped in a normal run —
  the frontier Concept's related-Concept jump — and it is announced in the log
  and the result bundle rather than passed over. Both related-Concept branches
  also assert that the sheet's "Related concepts" section and its chips agree,
  so a section promising jumps and offering none is a failure.
- **A planted Article (`-uitest-seed-article`).** The store wipe made the *store*
  known; it did not make the *reading* known. Analysis attaches Concepts by
  matching the Pack's vocabulary, so whether the newest Article had a Concept
  chip depended on what the news said that morning — and on 2026-08-18 it said
  nothing on the map, which is how the whole concept-sheet block had been
  skipping. `UITestSupport` now plants one unanalyzed Article naming seven
  flagship-Pack Concepts, and the app's own analysis is still what finds them.
  It is planted **already read**, because `rebuildCoreadLinks` scores *readings*
  — without one in the store, the Concepts on that sheet are Co-read with
  nothing and `3b-related-concept-jump` could never run. A step that can never
  run is not a step, so the reading is planted and the step is required.
- **47 `sleep()` calls became 0.** Waits name their condition: the feed header's
  own "Syncing…", the arXiv button's own "Added N fresh articles ✓", a Concept
  that has become Known, a tab that has become selected. Where the thing being
  waited for is an animation, `settle()` returns as soon as two consecutive
  frames match and prints when it gives up — the full map is still drifting at
  three seconds and says so.

**Verified** The suite as it stood was run first, green in 191.2s — and five of
its documented steps did not run in it. Their PNGs kept the dates of runs one to
five days earlier (`3-concept-sheet`, `3b`, `3c` from 17 Aug 16:52,
`4-marked-known` from 17 Aug 15:21, `5b4` from 13 Aug), so the previous day's
green run had skipped four of them too. The timestamps are the whole argument,
and they are exactly what nobody was looking at.

The rewritten suite is green with every required step run and the one skipped
step reported: **187.5s against the baseline's 191.2s**, while doing five steps
more than it did (190.1s on the full scheme, still under). Three of the four
tests are individually faster (16.9 vs 21.0, 39.0 vs 46.0, 19.0 vs 20.9); the
core journey is 112.6 against 103.4 because it now walks the block it used to
skip. 239 unit tests pass in 14.8s, and
Release still builds with the test hooks compiled out.

**Reviewed, then changed** The two-axis review earned its keep. The `Standards`
axis caught an unused `FileManager` seam in `ScreenshotEvidence` — ADR-0006
decided against exactly that ("a seam bought for a hypothetical is one more
thing to maintain") — and three constants hand-mirrored between the app and the
journeys under "if one changes, change both" comments. `Tests/Support` compiles
into the unit bundle, which *does* link the app, so `UITestLaunchTests` now
asserts the copies match instead of asking the reader to remember, and a third
test checks the planted Article still names at least five Pack Concepts. The
`Spec` axis caught the sharper one: `3b` and `5b4` were both declared optional
for a reason that is *always* true, so the coverage #30 wanted to save was still
evaporating — loudly, but evaporating. Planting the reading fixed half of that;
the other half is a defect in the Concept sheet, recorded below. Also gone: an
unreachable `else` in the import-picker step whose written reason described a
case the assertion above it had already ruled out, and a bare
`if action.exists { action.tap() }` in the quiz loop — the one branch left in
the file that was the exact shape the issue names.

**Flagged, not fixed: the Concept sheet ignores Semantic Links.**
`ConceptSheetView.relatedConcepts` reads `ConceptLink` only, so "Related
concepts" is empty for any Concept your reading has not joined to another.
ADR-0002 computes Semantic Links at install precisely so day one is not
"unconnected dust" — the map draws them, the sheet does not. That is why
`5b4-related-concept-jump` is optional, and it is a defect in the sheet rather
than in the journey: filed as **#33**, which carries "this step becomes
required" as one of its acceptance criteria.

**Learned** Two things. **The wipe was only half the state**: #26 made the store
known and everyone (this log included) treated the journey as deterministic
afterwards — but the feed is fetched from the internet at launch, so the
*reading* was still whatever the morning brought. A test whose subject arrives
by RSS is a test whose steps are optional. And **a conditional is a claim about
the world that nobody reads**: `if element.exists` said "this might not be here"
to no one, and the four steps it was silently skipping cost four days of a stale
screenshot going unnoticed. Saying it in a declaration, with the reason, turns
the same claim into something the run can print and the reviewer can argue with.

---

## 2026-08-18 — Explain now sends your Pack, and a test says so (#29)

**Built.** The decision from the entry below is in the code. `ExplainPrompt` is a
new pure type that builds both Explain prompts as data; `IntelligenceService.define`
asks it for one instead of assembling a string at the call site.

- **The opt-in path sends the term, the Active Pack's `field`, and its
  `clusterOrder`** — `Term the reader selected: LoRA / The field they are
  studying: AI Engineering / Areas of that field on their map: …`. No article
  text. Both values were already on `ActivePack`, so this needed no new data and
  no new fetch: `define` is already `@MainActor` and reads `ActivePack.inUse`.
- **The on-device path still sends the ±220-character excerpt**, and its
  instructions still say to use it. Two paths, two prompts, on purpose.
- **The system prompts diverged too, not just the payloads.** The opt-in one had
  to stop saying "use the excerpt to disambiguate" — there is no excerpt — and it
  now says the model is told the reader's field *and nothing about the document
  the term came from*. The injection rule is built per path for the same reason:
  a shared wording that mentioned "an excerpt" would invite the model to ask for
  one. That was a real red test, not a hypothetical — the first version shared
  one rule string and the exactness test caught the word.
- **The Cluster list is capped at 12.** A Pack author picks these so the count is
  not truly unbounded, but a payload that is a promise needs a ceiling, and the
  first Clusters carry the field's shape anyway.
- **Empty field or Clusters drop their line** rather than sending a blank one. A
  Pack is data and an imported one need not fill everything in; the model gets
  less signal, not a malformed prompt.

**What the review changed, which was the interesting half.** The first version
had pure, well-tested prompt builders and a *call site nothing covered*: swapping
the opt-in branch to `ExplainPrompt.onDevice` — one line, the exact #29
regression — left every test green. Tested builders were not the same thing as a
tested payload. So the tier became a value: `ExplainTier.choose(modelAvailable:hasKey:)`
and `ExplainPrompt.forTier`, called once in `define`, with the prompt and the
transport both following from the answer. `.optIn` is deliberately *handed* the
excerpt and must ignore it, which is what the test asserts. That mutation was then
run for real: red, three assertions, reverted.

Two more from the same review. The degradation test's skip branch asserted
`isModelAvailable || hasAnthropicKey` — which is `canDeepen`'s own definition read
back, so it could never fail; it now cross-checks the property the UI gates on
against the tier the prompt layer picks, two expressions that can actually drift.
And `ExplainPrompt.maxClusters = 12` collided with `PackFile.maxClusters = 10`,
which the validator already enforces — one ceiling now, the validator's.

**Verified** 223 unit tests pass, and the seam was mutation-checked rather than
assumed.

**The documents overclaimed, and the review caught that too.** "No article text"
was not true: the word you select *is* article text. Three documents now say what
is actually true — no *passage* of what you are reading leaves, and a word you
deliberately select is the most of an article that ever does. Fixing it by
restating the absolute would have been the #29 failure repeated inside the commit
that closes #29. `IntelligenceService`'s own file header still read "Nothing
leaves the device" — in the one file that owns the `AnthropicClient` call — and
onboarding still promised it unqualified where Settings already qualified it.
Both corrected.

**Learned** The seam was worth more than the fix. Changing the payload was twenty
lines; what took the failure off the table was that prompt construction is now a
pure function over the term and the Pack, so *what leaves the device* is a value
a test can hold. `AnthropicClient` stays non-injectable deliberately (ADR-0006):
transport was never what anyone got wrong, and the seam that would have caught
this is the one that got built — though the first attempt at it stopped one level
too shallow, and only a review that asked "what one-line change would this miss?"
found the gap. The documents were the other half: `PRIVACY.md`, `README.md` and
`ROADMAP.md` now say the same thing as the code, and ROADMAP records the
fallback-first precedence rather than listing two absolutes and leaving the
collision to be rediscovered.

---

## 2026-08-18 — Explain will disambiguate from your Pack, not from the article (#29)

**Decided, not yet built.** A grilling session settled #29, which #16's audit had
raised and left open. Recorded as
[ADR-0006](docs/adr/0006-explain-disambiguates-from-your-pack-not-from-the-article.md)
and a new `Egress` entry in `CONTEXT.md`; the code and the document corrections
are the implementation ticket.

- **The opt-in path will send the term, the Active Pack's field, and its Cluster
  names** — no article text. The reader's own map does the disambiguating the
  ±220-character excerpt used to. Anthropic learns "someone studying AI
  engineering asked what LoRA means" and never sees a document.
- **The on-device path keeps the excerpt**, deliberately. Nothing leaves the
  device there, so the better signal is free. Two paths, two prompts, on purpose.
- **Where fallback-first and the privacy stance conflict, fallback-first wins.**
  Both were listed as absolutes, which is how they came to contradict each other
  unnoticed. Dropping Explain on hardware without Apple Intelligence was the
  cleanest privacy answer and would have deleted the feature on the iPhone 14 Pro
  this app is actually read on — the device that is the reason the opt-in path
  exists.
- **`Egress` is now a term**: the closed, enumerated list of what leaves the
  device. The stance had no name, so "on-device by default", "nothing leaves the
  phone", "concept name/definition only" and "opt-in exception" were four
  phrasings of it that nobody could check against one another.
- **arXiv stays and joins the list** — a search term reaching a search API is the
  feature working, and proxying it would need the first-party server the product
  does not have.

**The cost, taken knowingly.** A word ambiguous *inside* the reader's own field —
"bias" statistically against "bias" in fairness — stops being separable, where the
sentence would have separated it. The field resolves the common collisions, and
the sentence-level cases are disproportionately words already on the map, which
never reach a model: `ArticleView.explain` matches an existing Concept first and
returns offline.

**Learned** Two things the interview surfaced that reading the code had not.
The first is that **the decision was upstream of the fix**: the issue offered
three options, and all three took "send an excerpt or don't" as the question,
when the real question was what the promise protects. Once that was *egress*
rather than *any model seeing article text*, a fourth option appeared that none
of the three had — use the Pack. The second is that **the missing word was the
root cause**. `CONTEXT.md` has had 17 precise terms and nothing for the privacy
stance, so four phrasings of it drifted apart across four documents with no
way to notice. The map has a name for everything the reader can see and had none
for the promise the product is built on.

---

## 2026-08-17 — The journey's verdict came from leftover data, not from the code (#26)

**Built**
- **`UITestSupport`** (`#if DEBUG` only) — a `-uitest-reset-store` launch argument
  that empties every model type and clears the seeding defaults before the first
  frame, so a journey starts from a known install. This had to come *first*: the
  bug could not be diagnosed without it, because the diagnostic loop kept
  mutating the state it depended on. Deletes row by row, not with
  `delete(model:)` — a batch delete does not maintain inverse relationships.
- **The core journey dismisses the Concept sheet through the affordance built for
  it** (`closeSheet`), not `app.swipeDown`. All four journeys now start from a
  wiped store, and the journey asserts the sheet closed and the tab became
  selected, so a swallowed tap names its own step.
- **A new guard, `testConceptSheetDismissesWhileScrolled`** — scrolls the sheet,
  then dismisses it, and checks the tab bar is live afterwards. It locks the
  invariant the fixed journey now leans on, and it asserts the sheet *did* scroll,
  so it cannot pass by not exercising the case.

**How it was actually found.** The reported cause — `swipeDown` absorbed by the
sheet's inner `ScrollView` — turned out to be **half right, and the missing half
was the whole bug**. A 15-second probe against a frontier Concept's sheet showed
`swipeDown` dismissing it perfectly. Only after scrolling the sheet first did the
probe go red, with the journey's exact symptom:
`sheetWasScrollable=true sheetStillOpenAfterSwipeDown=true knowledgeTabReached=false`.
So the gesture is *conditional*: it dismisses a sheet at scroll-top and merely
scrolls one that is not. Which is why the journey's fate depended on data — a
Concept with 17 Articles fills the sheet, XCUITest scrolls a row into view to tap
it, and the drill-through leaves the offset non-zero by the time line 81 swipes.

Then the loop broke the same way the journey had: the probe that was red twice
came back **skipped**, because an earlier probe had opened an Article, marked it
read, bumped Mastery and consumed the cluster's Frontier. Diagnosing a
state-dependent test with a state-dependent loop does not work, and that is what
forced the reset hook to be built before the fix rather than after.

**Verified** The full journey suite twice back to back, four tests green both
times (~193s each) — consecutive runs agreeing is the actual claim, since a
single green run is what this bug always produced. 211 unit tests still pass, and
Release still builds with the hook compiled out. Proof the wipe really wipes:
`10c-source-offer.png` now gets written, meaning the Pack-switch journey finally
exercises its source-offer branch instead of finding nothing left to offer.

**Learned** A gesture that competes with a scroll view is not a dismissal, it is
a coin flip weighted by content height. And the deeper one, filed as **#30**:
this suite has **15 branches guarded by `if element.exists`**, each of which
skips its own assertions and leaves the test green. That is how
`4-marked-known.png` went stale on 2026-08-13 and stayed unnoticed for four days
— the journey was passing while a documented step had silently stopped running.
Three defects today were the same shape: a test that could not fail. The stale
screenshot was the clue that cracked #26, and it was only found by comparing file
timestamps by hand.

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
- **`PRIVACY.md` was rewritten, not copied** — and then rewritten again, because
  the first draft was wrong in the same way its predecessors were. The original
  described a product that generates Packs, probes suggested feed URLs and shows
  a regulated-fields banner, so those claims came out. But the draft then
  repeated what `README.md` and `ROADMAP.md` both said: that the BYO-key path
  sends a Concept's name and definition and **never article text**.
  `/code-review`'s Standards axis read the claim against the source instead of
  against the other documents, and `IntelligenceService.define` sends a
  ±220-character window of article prose on exactly that path — has done since
  Explain started using the same client. Also undisclosed: `TopicSearchService`
  sends a Concept name to `export.arxiv.org`, a third outbound host. Both are now
  described; **#29** carries the decision of whether the excerpt should be sent
  at all, and the README and ROADMAP claims were corrected to stop asserting
  something false in the meantime.
- **Three issues filed, not two.** The privacy finding became #29 because it is
  not a wording call: either Explain stops sending the excerpt, or "nothing
  leaves the phone" acquires a caveat. That is a product decision and belongs in
  an ADR.
- **ROADMAP Horizon 5 item 16 said the wrong thing** — it described exporting
  the Pack so two apps could coexist, the option ADR-0001 rejected. Rewritten,
  along with item 17 ("validate in CareerPulse first" — there is nowhere to
  validate but here now). The dropped theme palettes are pointed at from
  Horizon 4 item 12 so they are findable rather than lost.
- **What the inventory turned up, as tickets.** **#27**: `PackDraft` and
  `PackGenerator` were on ADR-0001's port list and never ported, with no ticket
  covering them — the one place the port was genuinely incomplete rather than
  deliberately narrowed. **#28**: `TopicSearchService` still has no response size
  cap, unlike both its siblings. **#29**: the privacy claim above.

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

And the sharper version of the same lesson, from #29: **three documents agreeing
with each other look like corroboration and are one source.** README, ROADMAP and
a DEVLOG entry all said "never article text". Each was written from the one
before it, none from the code, and the claim was false for weeks in the document
a reader would trust most. The review caught it only because it was told to check
prose against source rather than against precedent.

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
