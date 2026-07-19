# TechPulse — Roadmap / Future Work

> Prioritized backlog of what to build next and why. Companion to
> [DEVLOG.md](DEVLOG.md) (what was built) and
> [CareerPulse-Template.md](CareerPulse-Template.md) §9 (the validated bets
> this list draws from). Ordered within each horizon; check items off or move
> them into DEVLOG entries as they land.

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

5. **Widgets + Live Activity.** Streak ring + "your next dot" on home/lock
   screen. The habit system already computes both; this is surface area, not
   new logic. Strongest cheap retention lever.

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
    - *Source health in Settings*: show each source's cached-article count
      and newest item date — a dead feed (Kaggle's Medium blog died in 2020)
      should be visible, not silent. Consider flagging sources whose newest
      item is > 6 months old.
    - *Full per-source fairness for the daily cap*: bootstrap (shipped) fixes
      day one; beyond that, very active feeds (arXiv, TechCrunch) can still
      crowd quiet weekly feeds out of the newest-first 30. Reserve a minimum
      slot per enabled source before filling the remainder newest-first.
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

13. **iPad / Mac layout.** The graph deserves a big canvas; NavigationSplitView
    + the same Canvas scales naturally.

14. **CloudKit E2E private sync.** Multi-device without a server of ours;
    opt-in; export = one JSON file, delete = wipe container (template §6).

15. **iOS 27 revisit** (README toolchain note): reorderable containers for
    topic cards, `LanguageModel` protocol as a cleaner seam for the BYO-key
    client, DataDetection in article text.

## Horizon 5 — Product line (background)

16. **Pack format + universal mode.** CareerPulse template §10 defines the
    runtime-generated pack JSON; TechPulse should be able to *export* its
    AI-engineer pack in that format (it doubles as the marketplace format).

17. **Mock-exam mode + expert packs** — the business engine per template §5;
    validate with one exam-pressure career in CareerPulse first.

---

## Standing constraints (unchanged by anything above)

- **Privacy:** on-device by default; the only network egress is public feed
  fetch + the opt-in BYO-key path (concept name/definition only, user's own
  key, no first-party server). Every new feature is measured against this.
- **Zero third-party dependencies** — still a feature.
- **Fallback-first:** every AI feature must work (degraded is fine) on
  hardware without Apple Intelligence — the reference device guarantees it.
- **Testing gate:** nothing ships without unit coverage for engine logic and
  a journey screenshot for every new screen — Settings taught us that the
  uncovered screen is where the shipped bug hides.
