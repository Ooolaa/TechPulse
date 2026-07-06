# TechPulse

Offline-first iOS app that aggregates AI/tech news, summarizes articles **on-device** (Foundation Models), and grows a visual knowledge map of concepts you've learned. Full product spec: [TechPulse-Build-Spec.md](TechPulse-Build-Spec.md). UI reference: [design/](design/).

## Status — Milestones 1–5 ✅ (M6 polish remaining)

- SwiftData models: `FeedSource`, `Article`, `Concept`, `LearningEvent`, `ConceptLink`
- Feed pipeline: RSS/Atom/RDF parsing, offline cache, pull-to-refresh, BackgroundTasks refresh
- On-device intelligence: Foundation Models summarization + concept extraction, NaturalLanguage fallback
- Knowledge engine: mastery scoring, embedding-based concept matching, "I know this", time decay
- Force-directed knowledge graph (Canvas + TimelineView) and Swift Charts progress views
- UI test (`Tests/UITests`) drives feed → article → concept sheet → graph and saves screenshots to `/tmp/techpulse_uitest`

Next: **M6 — polish** (quiz mode, App Intents/Siri, Liquid Glass pass, wider test coverage).

## Toolchain

Built for **iOS 26 / Swift 6.2 / Xcode 26.3** (the spec's iOS 27 targets are adapted down; revisit reorderable containers + `LanguageModel` protocol when Xcode 27 ships).

## Building

```bash
xcodegen generate        # regenerates TechPulse.xcodeproj from project.yml
open TechPulse.xcodeproj # or: xcodebuild -scheme TechPulse -destination 'generic/platform=iOS Simulator' build
```

The `.xcodeproj` is generated — edit `project.yml`, not the project file.
