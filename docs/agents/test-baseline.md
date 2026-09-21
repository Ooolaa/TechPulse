# Test baseline

What a clean run looks like, so an agent can tell a regression from the
environment it is standing in.

## Commands

| Scheme | Covers | Where |
| --- | --- | --- |
| `TechPulseUnitTests` | `TechPulseTests` only | simulator **or** physical device |
| `TechPulse` | `TechPulseTests` + `TechPulseUITests` | simulator only — the XCUITest runner can't be provisioned from the command line |

```bash
xcodebuild test -scheme TechPulseUnitTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Reading the result — three traps

1. **Never pipe `xcodebuild` through `head` or `tail`.** The per-test lines are
   the only place failures are named; truncating the log leaves a summary that
   says a run failed and nothing about what did.
2. **The shell exit code through a pipe is the pipe's.** `xcodebuild test | tail`
   exits 0 on a failed run. Use `set -o pipefail`, or grep for `** TEST FAILED **`.
3. **Read the `.xcresult`, not stdout.** The bundle path is printed at the end
   of every run:

```bash
xcrun xcresulttool get test-results tests --path <run>.xcresult
```

Walk `testNodes` recursively. A `Test Case` node carries `result: "Failed"`, and
its reason lives in a child of `nodeType: "Failure Message"`. Note that a failing
`Test Case` has children (`Arguments`, `Failure Message`), so a walk that only
counts childless nodes reports zero failures on a red run.

## The embedding failures are transient, not a floor

`SemanticLinker.embed` returns `nil` wherever `NLEmbedding` has no model. On a
simulator whose embedding asset has not been downloaded yet, that takes out
roughly **14 cases across 6 suites** — Concept de-duplication, Concept
neighbours, Hot candidates, Pack installer, Pack migration, Semantic linker —
and one UI journey, `testCoreJourney`. They fail three ways:

- `SemanticLinker.embed(…) → nil` directly.
- Empty results downstream — no Semantic Links after a Pack install, nothing on
  the frontier to jump to, spelling variants like *Threat Modelling* / *Threat
  Modeling* left as two dots because the merge had no vectors to judge with.
- **Performance assertions inverted.** With nothing embedded the work finishes
  too fast and trips its own floor: *"analysis cost 0.327s — 600 Concepts were
  not really embedded"*.

**This is a transient environment state, not a permanent property of the
simulator, and it resolves on its own.** Measured on 2026-09-21 against the same
`iPhone 17 Pro` / iOS 26.3.1, the same code, the same scheme:

| Time | Result |
| --- | --- |
| 09:53 | 14 cases failing across those 6 suites |
| 10:53 | **0 failing** — every one of those suites green |

Nothing in the repo changed between them to explain it: the failing test names
exist unaltered on `origin/main`, and no commit touched those files. The
embedding model became available to the simulator in between, most likely
downloaded on demand during the intervening runs.

**So: do not treat these as expected.** An earlier version of this file called
them "the simulator's floor" and told agents to ignore them, which was wrong in
the more dangerous direction — it would have had an agent wave through 14
genuine failures. If you see this cluster, the response is to **re-run**, and
to check whether the whole cluster moves together. A failure that persists
across runs once the embedding is warm is a real failure.

The honest summary: an all-embedding failure cluster means the environment is
cold; anything else means the code is broken. The real verification remains a
physical device — ROADMAP records the suite green on an iPhone 14 Pro, where
the fallback paths are first-class.

## The journeys share the same cause

The UI journeys run against the same `NLEmbedding`, so a cold environment takes
them out too. Measured while it was cold, `xcodebuild test -scheme
TechPulse -only-testing:TechPulseUITests`, `iPhone 17 Pro` / iOS 26.3.1:
**12 cases, 2 failing.**

- **`testCoreJourney` — the embedding cluster.** Three assertions, all downstream of the
  same nil: *"Semantic Links are computed for the whole Pack at install, so a
  frontier Concept no reading has met still has neighbours that mean something
  similar (#33)"*, the sheet offering chips but none under *Related in meaning*,
  and then the related-concept chip never appearing to tap. Re-run before
  believing it: this journey asserts a real product claim, and it passes once
  the embedding is warm.
- **`testStandingSourceOfferJourney` — not classified.** *"the row outlived the
  suggestions it was holding (waited 10s)"*. This one has no established link to
  the embedding, and it is a 10-second wait, which is the shape of a flake.
  Retry it once. If it reproduces, it is worth a look rather than an assumption
  — do not fold it into the embedding cluster on the strength of sitting next to
  one.

`set -o pipefail` reports exit 65 on this run, which is what a caller should
check. Note that the run's stdout names four distinct tests in its `error:`
lines and *started* lines; only two of them actually failed. Counting test names
out of the log over-reports. Read the `.xcresult`.
