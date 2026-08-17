# CareerPulse is retired, and this is what came across

ADR-0001 decided that TechPulse absorbs the runtime pack system and CareerPulse
retires as a separate app. That decision named the destination but not the
inventory: it left open what, exactly, was still only in CareerPulse. Until that
is written down, "retired" is indistinguishable from "abandoned mid-port", and
the answer decays — the source repo's last commit is 2026-07-31, and every week
that passes makes it less obvious to a future reader whether an absent feature
was rejected or forgotten.

**Decision:** The port from CareerPulse is **closed**. Its content is accounted
for file by file below, in one of three states — *brought across*, *tracked*, or
*dropped* — and nothing is left implicit. The repository stays as history and is
not deleted; nothing new is built in it.

The inventory is taken against CareerPulse at `af8ab0c`, comparing tracked files
in both repos. Thirteen files existed only in CareerPulse. File existence is not
the whole story, though — content can be CareerPulse-only inside a filename both
repos have — so the two items of that kind found by reading the shared files are
listed alongside them.

## Considered options

- **Announce the retirement without the inventory** — a line in the README of
  each repo and nothing more. Rejected: it is what ADR-0001 effectively did, and
  two and a half weeks later nobody could say from this repo whether the port
  was finished. The inventory is the whole value; the announcement is the cheap
  part.
- **Port everything still only in CareerPulse, so the answer is "all of it."**
  Tempting because it needs no judgement and leaves no list to maintain.
  Rejected: it would drag across 556 lines of onboarding wizard superseded by
  #7, a palette set that cannot work against adaptive tokens without design that
  does not exist, and a second built-in Pack nobody asked for — work justified
  by where it came from rather than by wanting it.
- **Delete the repository once the port closed.** Rejected, and #16 rules it out
  explicitly. It is the primary source the port was taken from: every "dropped"
  entry below is only checkable while it exists.

## Brought across

- **`Tests/UnitTests/U4SecurityTests.swift`** → `Tests/UnitTests/ByoKeyTests.swift`
  and one test in `RSSParserTests.swift`. This was the gap that mattered.
  `KeychainStore` and `AnthropicClient` were back-ported into TechPulse on
  2026-07-14 **without their tests**, and the XXE hardening landed the same day
  the same way — so three shipped security-relevant behaviours had their only
  coverage sitting in the repo being retired, against this repo's own standing
  testing gate. The Keychain round trip and the Anthropic request shape came
  across close to verbatim; both were mutation-checked, and both catch a real
  regression (removing `SecItemUpdate` from the save path, and renaming the
  `x-api-key` header, each turn them red).
- **`PRIVACY.md`** → `PRIVACY.md`, **rewritten rather than copied**. The original
  described a product that generates Packs, probes suggested feed URLs, and shows
  a regulated-fields banner. TechPulse does none of those, so the claims were
  removed rather than inherited.

  Writing it is what found **#29**, and the finding is the reason this file was
  worth bringing across at all. The first draft repeated what `README.md` and
  `ROADMAP.md` both said — that the BYO-key path sends a Concept's name and
  definition and *never article text*. `IntelligenceService.define` sends a
  ±220-character window of article prose on that path, and has since Explain
  started using the same client. Three documents agreed with each other and none
  agreed with the code. What the file now says was checked against the source
  rather than against its predecessors, which also turned up the undisclosed
  arXiv egress and an "exhausts memory" claim the 5 MB checks do not support.

## Tracked, not yet brought across

- **`Services/PackGenerator.swift`**, **`Services/PackDraft.swift`** and
  **`Tests/UnitTests/PackDraftTests.swift`** — tracked as **#27**. ADR-0001's
  port list explicitly includes "the draft and generator types", and epic #2
  promises a reader who "picks a field, **or generates one**". Neither was
  ported, and no ticket covered them, so this was the one place where the port
  was genuinely incomplete rather than deliberately narrowed. `PackDraft` is also
  a prerequisite for editing an imported Pack, and `FeedDiscovery` (which lives
  in the same file) is what would let #20 cap and probe an imported Pack's
  suggested Sources instead of trusting them.

## Dropped

- **The five accent palettes in `Views/Theme.swift`** (Ocean, Plum, Forest,
  Sunset, Mono). Epic #2 lists the theme picker as out of scope, and ROADMAP
  Horizon 4 item 12 already carries it. Dropped as a *port* specifically: those
  palettes are light-only, and TechPulse's tokens are adaptive light/dark pairs,
  so every palette needs a dark half that was never designed. The CareerPulse
  file is a reference for the hues, not a patch to apply.
- **The Registered Nurse Pack**, in CareerPulse's `Services/BuiltinPacks.swift`
  (~90 lines, `static var all: [PackFile] { [aiEngineer, registeredNurse] }`).
  Written to prove the formula generalizes beyond tech, which it did — and that
  was its whole job. TechPulse ships `ai-engineer` and `security-engineering`
  instead, so the proof is already banked by a *second* Pack existing, and a
  nursing Pack authored as a demo by someone who is not a nurse is worse than no
  nursing Pack. Dropped as content, not as a capability: it is a Pack file now,
  so anyone who wants it can author one without touching the app.
- **`Views/Onboarding/OnboardingWizard.swift`** — 556 lines whose job was picking
  or generating a field at first launch. Superseded: #7 shipped Pack selection
  and import as their own screen, and the onboarding step still wanted is the
  Reading Intention, which is #15's and has a different shape. The
  `Theme.paletteKey` picker plumbing in its Style step goes with the palettes
  above.
- **`Models/KnowledgePackRecord.swift`** — superseded by `InstalledPack.swift`,
  which #4 ported in its place.
- **`CareerPulseApp.swift`**, **`Tests/UITests/CareerPulseUITests.swift`**,
  **`CareerPulse.entitlements`** and the three **`CareerPulse.xcodeproj`** files
  — renamed twins of files TechPulse already has. The project files are moot
  here regardless: TechPulse generates its `.xcodeproj` from `project.yml`.

## Consequences

`ROADMAP.md` Horizon 5 item 16 described TechPulse exporting its Pack so the two
apps could coexist — the option ADR-0001 rejected — and item 17 proposed
validating mock-exam mode "in CareerPulse first". Both are rewritten by this
work. `DEVLOG.md` no longer heads itself with a sibling-project pointer.

Three things surfaced during the inventory. All three are the same failure —
a claim that was believed because it was written down somewhere, rather than
checked against what runs:

- **The privacy claim was wrong, in three documents at once.** `README.md`,
  `ROADMAP.md`'s standing constraints and a `DEVLOG.md` entry all said the
  BYO-key path sends a Concept's name and definition and never article text.
  `IntelligenceService.define` sends a ±220-character excerpt of the article on
  that path. The 2026-08-02 entry that produced those words reasoned about "Go
  deeper", where the claim holds, and nothing re-checked it when Explain began
  using the same client. The documents have been corrected to describe what runs;
  **#29** carries the decision underneath, which is whether the excerpt should be
  sent at all rather than how to word it. The lesson is in how it survived: three
  agreeing documents look like corroboration and are one source.
- **The XXE test asserted nothing.** Flipping
  `shouldResolveExternalEntities = false` to `true` leaves it green, because a
  `Data`-backed `XMLParser` never fetches the external resource either way. The
  original also asserted only through `allSatisfy` over what turns out to be an
  empty array — vacuously true. Kept as a regression guard on the outcome, with
  its limit written down, and paired with a benign control feed so that "no
  hostile item" cannot pass for the wrong reason.
- **`TopicSearchService` still has no response size cap**, unlike its two
  sibling fetchers. Tracked as **#28**. It is also a third outbound host, which
  `PRIVACY.md` now discloses.
