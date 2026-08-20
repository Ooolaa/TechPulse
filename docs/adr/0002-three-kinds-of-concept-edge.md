# Three kinds of Concept edge, not one

ADR-0001 made Packs user-generated, which removed the guarantee that the
authored Dependency graph is any good. That promoted "how Concepts get linked"
from a presentation detail to load-bearing logic, and the single existing edge
kind could not carry it.

**Decision:** Concepts are joined by three distinct edge kinds, stored and drawn
differently:

- **Dependency** — directed, authored as part of a Pack. "Learn A before B."
- **Semantic Link** — undirected, computed from Concept definitions when a Pack
  is installed. "These are about the same thing."
- **Co-read Link** — undirected, learned from reading and normalized. "You met
  these together."

Build order: Semantic Link first, then normalize the existing Co-read Link.

## Why not one kind

The existing single Link is raw pairwise co-occurrence, and it fails three ways
that a normalized version alone would not fix:

- `linkCooccurring` connects **every pair**, so an article with 8 Concepts emits
  28 Links — density grows quadratically with article richness.
- `weight` increments forever and is never normalized, so hub Concepts link to
  everything.
- The weight is invisible regardless: `ForceGraphView` draws
  `width: min(3, 0.8 + weight * 0.5)`, which saturates at weight ≈ 4.4, and the
  spring attraction is a constant — so weight drives neither line width past 5
  nor layout distance at all.

The decisive failure is **day one**. Co-occurrence requires reading history. A
freshly installed generated Pack has none, so the map opens as unconnected dust
and stays that way for weeks. Semantic Links are computable at install time from
the definitions the Pack already carries, using the sentence-embedding facility
already present in the codebase for Concept de-duplication — on-device, offline,
and with no dependency on Apple Intelligence.

## Consequences

`KnowledgePathEngine.frontier()` restricts recommendations to Pack Concepts
because article-discovered ones "have no dependency structure". Semantic Links
give them structure, so that restriction becomes revisitable — Concepts your own
reading discovers could earn their way into the Frontier rather than being
permanently second-class.

De-duplication currently gives up above 500 Concepts
(`guard cache.count < 500` in `KnowledgeEngine.embeddingMatch`). Semantic Links
raise the stakes on that cliff: near-duplicate Concepts would gain strong
Semantic Links to each other and visibly clutter the map.

**Amended (2026-08-20):** the cliff is gone — `ConceptIndex` holds each name's
meaning instead of recomputing it, which is what made the scan unaffordable and
bought the ceiling (#11). The stakes this consequence names are not yet
answered, though: measured against the shipped threshold, the embedding merges
neither a plural nor an abbreviation, so near-duplicates still accumulate at
every map size rather than only above 500. Calibrating that threshold against
real Concept names is the open half.
