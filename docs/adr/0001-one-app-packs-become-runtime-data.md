# One app: TechPulse absorbs the runtime pack system

TechPulse and CareerPulse had converged on the same product — a habit-driven
reading app over a knowledge map — differing only in where the map comes from.
TechPulse's `KnowledgePack` is a compile-time Swift `enum`; CareerPulse's is a
validated JSON `PackFile` installed at runtime. Keeping both meant hand-merging
every feature from TechPulse into CareerPulse indefinitely.

**Decision:** TechPulse absorbs the pack system. `KnowledgePack` stops being
compile-time data and becomes an installed Pack loaded at runtime. The AI
Engineer pack ships as the flagship built-in. CareerPulse retires as a separate
app.

## Considered options

- **CareerPulse absorbs TechPulse.** Its generic engine is already built and
  validated, so nothing moves forward. Rejected because the pile moving
  *backward* is far larger: widgets, Explain-on-selection, semantic zoom, the
  hot-topics radar, full-text fetch, quiz depth, adaptive dark mode and arXiv
  topic search all post-date CareerPulse's last re-sync (2026-07-12), and each
  is a hand-merge.
- **Keep both; TechPulse exports its pack in CareerPulse's format** — the
  option `ROADMAP.md` Horizon 5 item 16 already described. Rejected because it
  preserves the hand re-sync tax it was meant to avoid.

## Consequences

Curation stops being structural. `KnowledgePathEngine.frontier()` currently
restricts recommendations to `KnowledgePack.concepts` because *"stray
article-extracted concepts have no dependency structure and would otherwise all
count as 'ready', flooding recommendations with noise."* Once packs are
user-generated, that hand-authored dependency graph is no longer guaranteed to
be good — so how Concepts get linked stops being a presentation detail and
becomes load-bearing. See ADR-0002 if and when that algorithm is settled.
