# TechPulse — Roadmap / Future Work

> Prioritized backlog of what to build next and why. Companion to
> [DEVLOG.md](DEVLOG.md) (what was built) and
> [CareerPulse-Template.md](CareerPulse-Template.md) §9 (the validated bets
> this list draws from — a spec document that lives on in this repo; the app
> it named is retired, see [ADR-0005](docs/adr/0005-careerpulse-is-retired-and-what-came-across.md)).
> Ordered within each horizon; check items off or move them into DEVLOG entries
> as they land.

**Where the app stands:** M1–M6 complete, Knowledge Pack shipped (58 concepts
in 8 clusters, now including Data Science / Kaggle), habit system + "Go
deeper" + semantic zoom + full-text fetch + BYO Claude key + adaptive dark
mode + concept-sheet navigation all landed. Feeds seed incrementally and new
sources bootstrap outside the daily cap. Suite: 21 unit tests + 2 UI
journeys, verified in light and dark. Runs on the physical iPhone 14 Pro
(A16, no Apple Intelligence — the fallback paths are first-class).

---

## Horizon 1 — Finish what's started (days)

1. **Close the graph-perf measurement loop.** The `step()` settle cap + label
   cache shipped, but the DEVLOG's clean before/after CPU trace is still
   pending. Hold the app on the graph screen, `xctrace record --template
   'CPU Profiler'` for 10s on the device, confirm `step()` has left the top
   symbols, paste numbers into DEVLOG. *Done when: before/after % in DEVLOG.*

2. **Accessibility pass** (template §7 calls these non-negotiable, and the
   graph is currently a silent Canvas):
   - VoiceOver: per-dot labels on graph nodes (name + mastery state), or at
     minimum an accessible summary + the glossary strip as the fallback path.
   - Reduced Motion: freeze the force simulation and the ripple pulse.
   - Dynamic Type audit: the many fixed `.system(size:)` fonts should scale
     (at least for body/article text; `relativeTo:` where layout allows).
   *Done when: VoiceOver can walk a cluster, and Reduce Motion stills the map.*

3. **Dark-mode design reference.** `design/` mockups are light-only; the
   adaptive token layer now defines a de-facto dark design. Capture the
   journey screenshots (both modes) into `design/` so future UI work has a
   reference to match. *Done when: design/ has a dark set.*

4. **BYO-key polish.** Key validation on save (1-token ping → immediate
   feedback instead of failing later inside "Go deeper"), clearer error
   surfacing (the client's LocalizedError strings currently die in a
   `try?`), and a model picker (Sonnet default / Haiku for cost).
   *Done when: a bad key is caught at entry, and a Go-deeper failure says why.*

## Horizon 2 — Retention loop (weeks; highest product value per template §9)

5. ~~**Widgets.**~~ **Shipped.** Streak ring + "your next dot" across five
   families (small, medium, and the three lock-screen accessories). App writes
   a small `WidgetSnapshot` JSON to an App Group; the extension only decodes
   and renders — no SwiftData in a 30 MB widget process, and the app's store
   stays where it was (no migration). Forced two fixes worth keeping: the
   streak walk was duplicated in two views (now `HabitEngine`), and it returned
   0 until you'd read *that day*, so a morning widget read "0-day streak" on a
   live Streak — Streaks now carry a one-day grace.

   *Still open:* **Live Activity** was deliberately cut, not forgotten. Live
   Activities are for time-bound events that end within ~8–12h; a streak has no
   start or end and would squat on the lock screen forever — and the roadmap's
   "lock screen" goal is already met by the accessory families. If revisited,
   the honest shape is a *reading-session* activity: starts on the day's first
   article, shows the goal ring filling, auto-ends at goal or day rollover.
   Local ActivityKit updates only (push needs APNs, which the free team lacks).

6. **Spaced-repetition notifications.** Decay already exists in the mastery
   model; surface it: "3 concepts fading — 2-minute review?" as *local*
   notifications only (privacy stance unchanged). Respect the daily-goal
   philosophy: tiny, skippable, never guilt-tripping.

7. **Shareable map card.** Render the lit constellation to an image
   (ImageRenderer over the Canvas) with streak + concept count; share sheet
   only — nothing leaves the device except what the user explicitly shares.
   The brag loop is the only growth mechanic that fits the no-server stance.

## Horizon 3 — Intelligence depth (weeks)

8. **Resume/syllabus import.** On-device extraction seeds green dots
   (generalizes the resume trick that shipped in M6). Big first-session win
   for experienced users — an all-gray map demoralizes (template §4.5).

9. **Cited summaries.** Summary sentences link back to source paragraphs —
   hallucination guard, and the single biggest trust feature if summaries
   ever come from the BYO-key path too.

10. **Full-text fetch hardening.** The heuristic `<article>` extractor works
    for The Verge-class pages; add per-publisher fallbacks, paywall
    detection (don't cache a login wall as the article), and a test corpus
    of saved HTML fixtures per source.

11. **Quiz depth.** Distractors already come from the same cluster; add
    "which concept does this describe" from pack definitions (works without
    Apple Intelligence), and blueprint-weighted mock-exam mode later
    (template §9.5 — the strongest willingness-to-pay feature).

12. **Feed health & fairness** (lessons of the empty Data Science tag):
    - *Source health in Settings*: **shipped** (#14). Every fetch writes its
      outcome to the Source — `FeedSource.lastFailure`, cleared the moment it
      answers again — and `SourceHealth` derives what a row says from that plus
      the cache: what it last answered, how much you have to read offline, and
      — for a Source whose newest item is older than six months, as proposed
      here — that it is **likely dead**. Kaggle's Medium blog died in 2020 and
      nothing said so; a Source in that state now says so in red, with the
      month it last published.
    - *Full per-source fairness for the daily cap*: **shipped** (#45), though
      not as proposed here. Reserving a minimum slot per enabled source was
      rejected on arithmetic in
      [ADR-0009](docs/adr/0009-daily-intake-is-shared-between-sources-not-won-by-recency.md)
      — 13 Sources and a cap of 30 spends 28 of the 30 before the newest-first
      fill begins, so it is round-robin with a constant bolted on. The cap is
      allocated round-robin instead, and no per-source constant exists.
    - *Official Kaggle blog RSS watch*: r/kaggle (community Atom feed) is the
      live stand-in today; swap in kaggle.com's own feed if one ever ships
      (retirement mechanism for dead sources already exists in SeedData).
    - *Pack authoring loop*: the Data Science cluster came from a user
      request — new clusters now ship via `KnowledgePack.packVersion` bumps;
      template §4's Career Pack format is the long-term authoring path.

## Horizon 4 — Platform reach (months)

12. **Theme picker.** The adaptive-token refactor made palettes cheap: Theme
    is the single source of color truth now. Ocean (current) + Plum / Forest
    / Sunset / Mono per template §7; onboarding step + Settings row; mastery
    lightness ordering must survive every palette (color-blind safety).
    The five accent hues were built in CareerPulse (`Views/Theme.swift` at
    `af8ab0c`) and are a **reference, not a patch** — they are light-only, and
    every token here is a light/dark pair, so each palette needs a dark half
    that was never designed (ADR-0005).

13. **iPad / Mac layout.** The graph deserves a big canvas; NavigationSplitView
    + the same Canvas scales naturally.

14. **CloudKit E2E private sync.** Multi-device without a server of ours;
    opt-in; export = one JSON file, delete = wipe container (template §6).

15. **iOS 27 revisit** (README toolchain note): reorderable containers for
    topic cards, `LanguageModel` protocol as a cleaner seam for the BYO-key
    client, DataDetection in article text.

## Horizon 5 — Product line (background)

16. ~~**Pack format + universal mode.**~~ **Superseded, and the old wording was
    wrong.** This item used to say TechPulse should *export* its AI-engineer pack
    in CareerPulse's format so the two apps could coexist — the option
    [ADR-0001](docs/adr/0001-one-app-packs-become-runtime-data.md) rejected,
    because it preserves the hand re-sync tax it was meant to avoid. There is one
    app. Packs are runtime data in it, the AI Engineer Pack is a built-in Pack
    file rather than a Swift `enum`, and `PackInstaller.exportActivePack` already
    emits the format — which is the marketplace format, so nothing here was lost
    but the two-app plan.

    CareerPulse is retired. What came across, what is still tracked (#27) and
    what was dropped is recorded file by file in
    [ADR-0005](docs/adr/0005-careerpulse-is-retired-and-what-came-across.md).
    The repo stays as history; nothing new is built there.

    *Still open from the original intent:* a **Pack marketplace** — Packs
    installable from somewhere other than a file someone sent you. Explicitly out
    of scope for the pack-driven epic, and it needs the trust questions answered
    first (who authored a Pack, what a generated one may claim), so it is a
    conversation before it is a ticket.

17. **Mock-exam mode + expert packs** — the business engine per template §5, and
    the strongest willingness-to-pay feature in it. Validate with one
    exam-pressure field as a Pack in this app: with Packs as runtime data, that
    is authoring a Pack file, not forking an app.

---

## Standing constraints (unchanged by anything above)

- **Privacy:** on-device by default, no first-party server, and **Egress** — the
  full list of what leaves the device — enumerated in [PRIVACY.md](PRIVACY.md).
  No passage of what you are reading is on that list; a word you select is the
  most of an article that ever leaves. Every new feature is measured against the
  stance, and against saying what it actually does; a feature that adds a line
  to the list is changing the promise, not adding a detail. The list has five
  entries. #58 added one — a **Probe** of a suggested Source at the moment the
  reader accepts it — which is the same request as reading that Source, a moment
  earlier, and carries nothing about the reader.
- **Zero third-party dependencies** — still a feature.
- **Fallback-first:** every AI feature must work (degraded is fine) on
  hardware without Apple Intelligence — the reference device guarantees it.
- **When fallback-first and privacy collide, fallback-first wins**
  ([ADR-0006](docs/adr/0006-explain-disambiguates-from-your-pack-not-from-the-article.md)).
  These two were listed side by side as absolutes, which is how they came to
  contradict each other unnoticed in the Explain path: the answer is to change
  **what a feature sends**, never to delete the feature on hardware without
  Apple Intelligence. That hardware is the reference device, and it is why the
  opt-in path exists at all.
- **Testing gate:** nothing ships without unit coverage for engine logic and
  a journey screenshot for every new screen — Settings taught us that the
  uncovered screen is where the shipped bug hides.
