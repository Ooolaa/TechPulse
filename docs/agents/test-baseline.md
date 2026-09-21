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

## The embedding baseline

`SemanticLinker.embed` returns `nil` wherever `NLEmbedding` has no model — which
includes the iOS simulator. This is a declared degradation path, not a defect:
the map is poorer and the install still works.

Measured on the simulator, 2026-09-21, `iPhone 17 Pro` / iOS 26.3.1:
**513 tests in 49 suites, 14 cases failing in 6 suites.** All 14 trace to that
one nil. The suites are Concept de-duplication, Concept neighbours, Hot
candidates, Pack installer, Pack migration, Semantic linker, and they fail three
ways:

- `SemanticLinker.embed(…) → nil` directly.
- Empty results downstream — no Semantic Links after a Pack install, nothing on
  the frontier to jump to, spelling variants like *Threat Modelling* / *Threat
  Modeling* left as two dots because the merge had no vectors to judge with.
- **Performance assertions inverted.** With nothing embedded the work finishes
  too fast and trips its own floor: *"analysis cost 0.327s — 600 Concepts were
  not really embedded"*.

**Treat these 14 as the simulator's floor, not as work.** A run that reports
them and nothing else is green. Escalate only a failure outside these suites, or
a count above 14. The real verification is a physical device — ROADMAP records
the suite green on an iPhone 14 Pro, where the fallback paths are first-class.

## The journeys inherit the same floor

The UI journeys run against the same absent `NLEmbedding`, so the floor is not
confined to the unit suite. Measured the same day, `xcodebuild test -scheme
TechPulse -only-testing:TechPulseUITests`, `iPhone 17 Pro` / iOS 26.3.1:
**12 cases, 2 failing.**

- **`testCoreJourney` — the floor.** Three assertions, all downstream of the
  same nil: *"Semantic Links are computed for the whole Pack at install, so a
  frontier Concept no reading has met still has neighbours that mean something
  similar (#33)"*, the sheet offering chips but none under *Related in meaning*,
  and then the related-concept chip never appearing to tap. Expected on the
  simulator. The journey is asserting a real product claim; the simulator simply
  cannot satisfy it.
- **`testStandingSourceOfferJourney` — not classified.** *"the row outlived the
  suggestions it was holding (waited 10s)"*. This one has no established link to
  the embedding, and it is a 10-second wait, which is the shape of a flake.
  Retry it once. If it reproduces, it is worth a look rather than an assumption
  — do not fold it into the floor on the strength of sitting next to one.

`set -o pipefail` reports exit 65 on this run, which is what a caller should
check. Note that the run's stdout names four distinct tests in its `error:`
lines and *started* lines; only two of them actually failed. Counting test names
out of the log over-reports. Read the `.xcresult`.
