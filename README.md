# TechPulse

Offline-first iOS app that aggregates AI/tech news, summarizes articles **on-device** (Foundation Models), and grows a visual knowledge map of concepts you've learned. Full product spec: [TechPulse-Build-Spec.md](TechPulse-Build-Spec.md). UI reference: [design/](design/).

**Privacy:** on-device by default, and no server of ours exists, so the "Data Not Collected" App Store label applies. Every outbound connection, and exactly what each one carries, is enumerated in [PRIVACY.md](PRIVACY.md) — **no passage of what you are reading is on that list**, only words you deliberately select. The opt-in exception is your own Claude API key (Settings → AI engine), which unlocks "Go deeper" and Explain on hardware without Apple Intelligence: "Go deeper" sends a concept's name, definition and cluster; Explain sends the word you selected plus your Pack's field and Cluster names, so your own map disambiguates the word instead of the article around it ([ADR-0006](docs/adr/0006-explain-disambiguates-from-your-pack-not-from-the-article.md), #29). On hardware with Apple Intelligence, Explain uses the surrounding sentence and stays on the device.

## Status — All milestones (M1–M6) complete ✅

- SwiftData models: `FeedSource`, `Article`, `Concept`, `LearningEvent`, `ConceptLink`
- Feed pipeline: RSS/Atom/RDF parsing, offline cache, pull-to-refresh, BackgroundTasks refresh
- On-device intelligence: Foundation Models summarization + concept extraction, NaturalLanguage fallback
- Knowledge engine: mastery scoring, embedding-based concept matching, "I know this", time decay
- Force-directed knowledge graph (Canvas + TimelineView) and Swift Charts progress views
- UI test (`Tests/UITests`) drives feed → article → concept sheet → graph and saves screenshots to `/tmp/techpulse_uitest`. Each journey that takes screenshots declares its steps up front: a step that does not run fails the test, and its screenshot has to have been written by that run

Knowledge Pack (skill tree): ~50 pre-seeded AI-engineer concepts in 7 clusters with dependency arrows, cluster overview + detail screens, frontier detection ("ready to learn"), gap detector with feed recommendations, and the staged learning path on Progress.

M6 added: on-device quiz mode (+0.3 mastery rule), resume-seeded knowledge base, Siri App Intent ("What did I learn this week?"), cache pruning (read articles >60 days), UX pass (day groups, unread dots, chip states, related concepts, cluster filters, recenter), and a test suite: 11 Swift Testing unit tests + 2 XCUITest journeys with screenshot capture.

Post-M6 (see [DEVLOG.md](DEVLOG.md) for dates):

- **Atomic Habits reading system** — 30 fresh articles/day intake cap, tiny daily goal card (ring + streak + goal-met celebration), goal picker.
- **Article concept primer** ("know these before you read"), word-level text selection, original-link storage with Safari/Share buttons.
- **"Go deeper"** — expands any concept into 3–5 linked sub-concepts on its island; on-device by default, or via your own Claude key on hardware without Apple Intelligence.
- **Explain** — select a word in an article and it joins your map as a Concept. On-device the surrounding sentence disambiguates it; on the BYO-key path your Pack's field and Clusters do, so nothing but the word itself leaves the device (ADR-0006).
- **Full-text fetch** — articles that arrive as feed snippets pull the real story from the publisher page, then regenerate the on-device summary.
- **Semantic zoom** on the knowledge graph — zooming spreads positions while dots/lines/labels stay constant screen size, so overview overlap always resolves; collision-culled labels; tap-a-dot glossary strip. Cluster (dependency) trees carry the same zoom, with pinch hint + recenter.
- **Parser hardening** — XXE / external entities disabled; entitlements file for Keychain access (BYO-key storage).
- **Adaptive dark mode** — every theme token carries a light/dark pair; mastery colors stay constant in both modes (color-blind-safe lightness order preserved).

## Toolchain

Built for **iOS 26 / Swift 6.2 / Xcode 26.3** (the spec's iOS 27 targets are adapted down; revisit reorderable containers + `LanguageModel` protocol when Xcode 27 ships).

## Building

```bash
xcodegen generate        # regenerates TechPulse.xcodeproj from project.yml
open TechPulse.xcodeproj # or: xcodebuild -scheme TechPulse -destination 'generic/platform=iOS Simulator' build
```

The `.xcodeproj` is generated — edit `project.yml`, not the project file.
