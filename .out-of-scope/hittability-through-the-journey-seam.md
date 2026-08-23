# Hittability through the `Journey` seam

The UI journeys read `isHittable` directly off an `XCUIElement`, and that is
fine. There will be no `Journey.isHittable(_:) -> Bool?`, no `isHittable` field
on `ElementState`, and no combined snapshot-plus-hittability read.

## Why this is out of scope

The proposal was a continuation of #48 → #53. Those closed a real bug: `exists`
then `label` is two queries against a moving app, and a control that goes
between them makes the second one **throw** rather than answer — a thrown query
reads as a broken journey rather than a failing one, which is how #48 lasted as
long as it did. `ElementState` and `waitUntil` exist to make that shape
unwritable.

`isHittable` was the survivor: it cannot go on `ElementState`, because XCUITest
does not carry hittability on `XCUIElementSnapshot`, so it cannot be read in the
same query as `label` / `isEnabled` / `isSelected`. That part is true and still
is. The proposal assumed the rest followed — that a two-query hittability read
carries the same throwing risk, and therefore needed a catching accessor of its
own.

**It does not. `isHittable` answers `false` for a control that is not there; it
does not raise.** Measured 2026-08-23 against a query matching nothing, which is
the state a vanished control leaves behind — the same fixture
`JourneyReadTests.testStateOfSomethingNotThereIsNilRatherThanAThrownQuery` uses:

```swift
let gone = app.buttons["noSuchControlInThisApp"].firstMatch
XCTAssertFalse(gone.exists)
let hittable = gone.isHittable   // answers false; does not throw
```

The trace shows why: `isHittable` re-resolves the query (`Find the … Button`,
retry 1, retry 2) and tolerates no-match, the way `exists` does. It is not one
of the attribute properties that raise `Failed to get matching snapshot: No
matches found…`. So hittability is not the `label` problem wearing a different
hat — it is in the class of reads that answer rather than throw, and it needs no
seam to make it safe.

That leaves nothing for an accessor to buy. It would add a second way to read a
control through `Journey`, to catch an exception that is never thrown.

## Two things this does *not* license

**The `label` / `isEnabled` / `isSelected` rule is untouched.** Those still
throw, they still go through `Journey.state(of:)` and `waitUntil`, and there is
still deliberately no wait taking a bare `() -> Bool`. This is a fact about one
attribute, not a softening of the seam.

**The direct `isHittable` assertions in the journeys must stay direct.** Both
call sites bypass `Journey.tap` on purpose:

```swift
// TechPulseUITests.swift — the #26 guard: a scrolled sheet's close button
// must still be reachable.
XCTAssertTrue(close.exists && close.isHittable,
              "close button not reachable once the sheet is scrolled")

// TechPulseUITests.swift — "every tab reachable, primary controls hittable".
XCTAssertTrue(button.isHittable, "\(tab) tab not hittable")
```

`Journey.tap` *tolerates* non-hittability by design — it polls for it and taps
anyway, because a row below the fold is not hittable until `tap()` scrolls it
into view. At these two sites hittability **is the assertion**. Routing them
through `journey.tap` would look like a tidy conversion to the seam and would
silently delete both guards. Don't.

## Prior requests

- #54 — "Hittability cannot go through the seam, so two journey lines still
  read a control twice"
