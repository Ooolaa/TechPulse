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
in both repos. Thirteen files existed only in CareerPulse.

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
  removed rather than inherited; what remains is checked against the code.

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
- **`Views/Onboarding/OnboardingWizard.swift`** — 556 lines whose job was picking
  or generating a career at first launch. Superseded: #7 shipped Pack selection
  and import as their own screen, and the onboarding step still wanted is the
  Reading Intention, which is #15's and has a different shape.
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

Two things surfaced during the inventory that are worth naming, because both are
about *believing* a claim rather than checking it:

- **The XXE test asserted nothing.** Flipping
  `shouldResolveExternalEntities = false` to `true` leaves it green, because a
  `Data`-backed `XMLParser` never fetches the external resource either way. The
  original also asserted only through `allSatisfy` over what turns out to be an
  empty array — vacuously true. It is kept, honestly documented, as a regression
  guard on the outcome rather than as evidence about the flag.
- **`TopicSearchService` still has no response size cap**, unlike its two
  sibling fetchers, so `PRIVACY.md` claims the cap for feed and article fetches
  only. Tracked as **#28**.
