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
