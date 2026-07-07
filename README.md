# TechPulse

Offline-first iOS app that aggregates AI/tech news, summarizes articles **on-device** (Foundation Models), and grows a visual knowledge map of concepts you've learned. Full product spec: [TechPulse-Build-Spec.md](TechPulse-Build-Spec.md). UI reference: [design/](design/).

## Status — All milestones (M1–M6) complete ✅

- SwiftData models: `FeedSource`, `Article`, `Concept`, `LearningEvent`, `ConceptLink`
- Feed pipeline: RSS/Atom/RDF parsing, offline cache, pull-to-refresh, BackgroundTasks refresh
- On-device intelligence: Foundation Models summarization + concept extraction, NaturalLanguage fallback
- Knowledge engine: mastery scoring, embedding-based concept matching, "I know this", time decay
- Force-directed knowledge graph (Canvas + TimelineView) and Swift Charts progress views
- UI test (`Tests/UITests`) drives feed → article → concept sheet → graph and saves screenshots to `/tmp/techpulse_uitest`

Knowledge Pack (skill tree): ~50 pre-seeded AI-engineer concepts in 7 clusters with dependency arrows, cluster overview + detail screens, frontier detection ("ready to learn"), gap detector with feed recommendations, and the staged learning path on Progress.

M6 added: on-device quiz mode (+0.3 mastery rule), resume-seeded knowledge base, Siri App Intent ("What did I learn this week?"), cache pruning (read articles >60 days), UX pass (day groups, unread dots, chip states, related concepts, cluster filters, recenter), and a test suite: 11 Swift Testing unit tests + 2 XCUITest journeys with screenshot capture.

## Toolchain

Built for **iOS 26 / Swift 6.2 / Xcode 26.3** (the spec's iOS 27 targets are adapted down; revisit reorderable containers + `LanguageModel` protocol when Xcode 27 ships).

## Building

```bash
xcodegen generate        # regenerates TechPulse.xcodeproj from project.yml
open TechPulse.xcodeproj # or: xcodebuild -scheme TechPulse -destination 'generic/platform=iOS Simulator' build
```

The `.xcodeproj` is generated — edit `project.yml`, not the project file.
