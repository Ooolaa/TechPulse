# TechPulse

Offline-first iOS app that aggregates AI/tech news, summarizes articles **on-device** (Foundation Models), and grows a visual knowledge map of concepts you've learned. Full product spec: [TechPulse-Build-Spec.md](TechPulse-Build-Spec.md). UI reference: [design/](design/).

## Status — Milestone 1 (skeleton) ✅

- SwiftData models: `FeedSource`, `Article`, `Concept`, `LearningEvent`, `ConceptLink`
- Tab navigation (Feed / Knowledge / Progress / Settings) styled to the design mockups
- Nine default AI feed sources seeded on first launch, toggleable in Settings
- Mastery color system (gray = new, blue = learning, green = known) implemented in `Theme.swift`

Next: **M2 — feed pipeline** (RSS parsing, offline cache, BackgroundTasks).

## Toolchain

Built for **iOS 26 / Swift 6.2 / Xcode 26.3** (the spec's iOS 27 targets are adapted down; revisit reorderable containers + `LanguageModel` protocol when Xcode 27 ships).

## Building

```bash
xcodegen generate        # regenerates TechPulse.xcodeproj from project.yml
open TechPulse.xcodeproj # or: xcodebuild -scheme TechPulse -destination 'generic/platform=iOS Simulator' build
```

The `.xcodeproj` is generated — edit `project.yml`, not the project file.
