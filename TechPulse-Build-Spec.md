# TechPulse — Offline Tech/AI News & Knowledge Map (iOS 27)

> **Purpose of this file:** A complete build specification you can hand to Claude Code.
> Suggested first prompt: *"Read TechPulse-Build-Spec.md and scaffold the Xcode project for Milestone 1."*

---

## 1. Product Overview

An **offline-first iOS app** that:

1. Aggregates the newest technology & AI news (RSS/APIs) when online.
2. Caches everything locally so reading works fully offline.
3. Uses **on-device AI** (Foundation Models framework) to summarize articles and extract key concepts.
4. Tracks which concepts the user **already knows** vs. **newly learned**.
5. **Visualizes** the user's knowledge as charts (radar map, growth timeline, heatmap).

**Target:** iOS 27+, iPhone (foldable-ready layout optional), Swift 6.4, Xcode 27.

---

## 2. Tech Stack & Rationale

| Technology | Used For | Why |
|---|---|---|
| **Swift 6.4** | Language | Async `defer` for safe cleanup in async pipelines; strict concurrency with less annotation boilerplate; free Foundation performance gains (e.g., faster URL parsing). |
| **SwiftUI (iOS 27 / 2026 release)** | Entire UI | Native reorderable containers (drag to rearrange topic cards in any container); DataDetection framework for smart link/date recognition in article text; item-binding alerts/dialogs. |
| **Liquid Glass (2nd iteration)** | Design system | Native iOS 27 look; use updated design tokens; verify readability with the new transparency control. |
| **Foundation Models framework** | On-device AI | Runs offline, private, zero API cost. Summarization, concept extraction, quiz generation. Use `@Generable` structured output. Optionally plug larger models via the new `LanguageModel` protocol when online. |
| **SwiftData** | Persistence | Offline-first store for articles, concepts, mastery levels. Native SwiftUI observation integration. CloudKit sync optional later. |
| **Swift Charts** | Visualization | Radar/bar/line/heatmap of knowledge state; native, performant, declarative. |
| **BackgroundTasks (BGAppRefreshTask)** | Feed sync | Fetch new articles periodically when device is online/charging. |
| **URLSession** | Networking | Fetch RSS/JSON feeds; download for offline cache. |
| **NaturalLanguage / Foundation Models** | Concept matching | Embedding/similarity to map extracted concepts against the user's known-concept list. |
| **App Intents** | Siri integration | New Siri (iOS 27) supports multi-step commands — "What did I learn this week?" queries the app directly. |
| **Swift Testing** | Tests | Modern testing framework, replaces XCTest for new code. |

---

## 3. Architecture

```
┌─────────────────────────────────────────────────┐
│                    SwiftUI Views                 │
│  FeedView · ArticleView · KnowledgeMapView       │
│  ConceptListView · SettingsView                  │
└──────────────────────┬──────────────────────────┘
                       │ @Observable / @Query
┌──────────────────────┴──────────────────────────┐
│                 App Services layer               │
│  FeedSyncService (BackgroundTasks + URLSession)  │
│  IntelligenceService (Foundation Models)         │
│  KnowledgeEngine (concept matching + scoring)    │
└──────────────────────┬──────────────────────────┘
                       │
┌──────────────────────┴──────────────────────────┐
│                    SwiftData                     │
│  Article · Concept · LearningEvent · FeedSource  │
└─────────────────────────────────────────────────┘
```

**Pipeline:** BackgroundTasks pulls feeds → SwiftData stores raw articles → Foundation Models summarizes + extracts concepts on-device → KnowledgeEngine compares against known concepts → Swift Charts renders the knowledge map.

---

## 4. Data Models (SwiftData)

```swift
import SwiftData
import Foundation

@Model
final class FeedSource {
    var name: String
    var url: URL
    var category: String        // "AI", "Mobile", "Web", "Hardware"...
    var isEnabled: Bool
    var lastFetched: Date?
    init(name: String, url: URL, category: String, isEnabled: Bool = true) { ... }
}

@Model
final class Article {
    @Attribute(.unique) var guid: String
    var title: String
    var content: String          // full text cached for offline
    var summary: String?         // generated on-device
    var publishedAt: Date
    var sourceName: String
    var isRead: Bool
    var readAt: Date?
    @Relationship var concepts: [Concept]
    init(...) { ... }
}

@Model
final class Concept {
    @Attribute(.unique) var name: String   // e.g. "RAG", "Swift Concurrency"
    var category: String
    var masteryLevel: Double     // 0.0 (new) … 1.0 (mastered)
    var firstSeen: Date
    var lastReviewed: Date?
    var isMarkedKnown: Bool      // user said "I already know this"
    @Relationship(inverse: \Article.concepts) var articles: [Article]
    init(...) { ... }
}

@Model
final class LearningEvent {
    var date: Date
    var kind: String             // "read", "markedKnown", "quizPassed"
    var conceptName: String
    var masteryDelta: Double
    init(...) { ... }
}
```

---

## 5. On-Device Intelligence (Foundation Models)

Use structured generation so output maps directly to models:

```swift
import FoundationModels

@Generable
struct ArticleAnalysis {
    @Guide(description: "3-sentence plain-language summary")
    var summary: String
    @Guide(description: "5-10 key technical concepts mentioned")
    var concepts: [ExtractedConcept]
}

@Generable
struct ExtractedConcept {
    var name: String
    var category: String
    @Guide(description: "One-line beginner explanation")
    var definition: String
}

func analyze(_ article: Article) async throws -> ArticleAnalysis {
    let session = LanguageModelSession(
        instructions: "You extract technical concepts from tech/AI news articles."
    )
    let response = try await session.respond(
        to: article.content,
        generating: ArticleAnalysis.self
    )
    return response.content
}
```

**Rules:**
- All analysis happens on-device → works offline, no API keys.
- Check `SystemLanguageModel.default.availability` and degrade gracefully (keyword extraction via NaturalLanguage as fallback).
- Batch analysis during BackgroundTasks windows to save battery.
- Optional: quiz generation ("Test me on this week's concepts") via the same session.

---

## 6. Knowledge Engine

- When concepts are extracted, match against existing `Concept` records (case-insensitive + embedding similarity via NaturalLanguage to catch "LLM" ≈ "Large Language Model").
- **Mastery scoring:**
  - New concept seen → mastery 0.1
  - Article read containing concept → +0.1
  - User taps "I know this" → set 1.0, `isMarkedKnown = true`
  - Quiz passed → +0.3
  - Time decay: -0.05/month without review (spaced-repetition flavor)
- Every change writes a `LearningEvent` (fuel for the timeline chart).

---

## 7. Visualization ("the expression") — Knowledge Graph (dots → net)

**Primary view: a growing force-directed knowledge graph.**

- Every **concept = a dot (node)**. New concepts appear as small dim dots.
- Two concepts appearing in the **same article** get connected by an **edge** — the net literally builds up as the user reads.
- **Node size** grows with mastery level; **color** encodes state (gray = new, blue = learning, green = known/mastered).
- **Edge thickness** = number of articles where the two concepts co-occurred (store as a `ConceptLink` model).
- Physics: force simulation (node repulsion + spring attraction on edges + centering force), rendered with `TimelineView` + `Canvas` for smooth animation.
- Interactions: tap a dot → concept detail sheet (definition, related articles, "I know this" button); pinch to zoom; drag to pan.
- Payoff: day 1 shows a few lonely dots; after weeks it's a dense living net of everything the user has learned about AI.

Add to data models:

```swift
@Model
final class ConceptLink {
    var conceptA: String        // Concept.name
    var conceptB: String
    var weight: Int             // co-occurrence count
    init(conceptA: String, conceptB: String, weight: Int = 1) { ... }
}
```

Secondary views (Swift Charts, native):
1. **Growth timeline** — cumulative concepts learned per week from `LearningEvent`.
2. **Reading streak** — BarMark of articles read per day.

UI notes:
- Topic/concept cards use the new **reorderable** API so users can prioritize their learning areas by dragging.
- Article text uses **DataDetection** so URLs/dates are tappable.
- Adopt Liquid Glass materials for chart cards; test with transparency control enabled.

---

## 8. Offline & Sync Strategy

- `BGAppRefreshTask` registered for periodic feed fetch (respect system scheduling).
- On fetch: parse RSS (use `XMLParser` or a lightweight Swift package), fetch full article text, store in SwiftData.
- Never require network to open the app: all views query SwiftData only.
- **Content focus: everything AI.** Default feed sources (user-editable):
  - arXiv cs.AI, cs.LG, cs.CL (research papers)
  - Hugging Face blog (models & open source)
  - OpenAI / Anthropic / Google DeepMind / Meta AI blogs (frontier labs)
  - MIT Technology Review — AI section
  - The Verge AI / VentureBeat AI (industry news)
  - Import AI / Ben's Bites style newsletters (RSS where available)
  - Categories become graph clusters: "LLMs", "Agents", "Vision", "Robotics", "Hardware/Chips", "Policy/Safety", "Open Source".
- Show a subtle "last synced" indicator; no blocking spinners.

---

## 9. App Intents (Siri)

```swift
struct WeeklyLearningIntent: AppIntent {
    static let title: LocalizedStringResource = "What did I learn this week?"
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // query LearningEvents from past 7 days, return spoken summary
    }
}
```

Also expose: "Mark <concept> as known", "Read me today's AI summary".

---

## 10. Milestones (build order for Claude Code)

1. **M1 — Skeleton:** Xcode 27 project, Swift 6.4, SwiftData models, tab navigation (Feed / Knowledge / Settings), seed feed sources.
2. **M2 — Feed pipeline:** RSS parsing, URLSession fetch, offline cache, FeedView + ArticleView, BackgroundTasks registration.
3. **M3 — Intelligence:** Foundation Models integration, `@Generable` analysis, availability fallback, concept storage.
4. **M4 — Knowledge Engine:** matching, mastery scoring, LearningEvents, "I know this" interactions.
5. **M5 — Visualization:** Swift Charts knowledge map (radar, timeline, heatmap, streak), reorderable topic cards.
6. **M6 — Polish:** Liquid Glass design pass, App Intents, quiz mode, widgets (optional), Swift Testing coverage.

---

## 11. Constraints & Notes for Claude Code

- Minimum deployment target: **iOS 27.0** (Foundation Models + new SwiftUI APIs).
- Strict concurrency on; prefer `actor` for services touching shared state.
- No third-party dependencies unless necessary (an RSS parser package is acceptable).
- All AI features must degrade gracefully on devices without Apple Intelligence.
- Privacy: no analytics; no data leaves the device **unless the user adds their own Claude API key** (Settings → AI engine) to unlock "Go deeper" on hardware without Apple Intelligence. In that opt-in case, only the concept name, its definition, and its cluster — never article text — go directly to `api.anthropic.com` under the user's own key; nothing routes through a server of ours, so the "Data Not Collected" App Store label still holds. State it this way in App Store copy: on-device by default, one user-controlled exception. The BYO-key path must keep instructions system-side only and accept typed JSON output.
- File layout: `Models/`, `Services/`, `Views/`, `Intents/`, `Tests/`.
