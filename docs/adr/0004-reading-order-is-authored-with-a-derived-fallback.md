# Reading order is authored, with a derived fallback

The Frontier is derived — Concepts whose Dependencies are all Lit. It is a
*set*, and usually holds several Concepts at once. Something has to reduce it to
the one **Next Dot** the app promises, and today that something is authored:
`KnowledgePathEngine.nextDot` flattens `KnowledgePack.stages` into a `pathOrder`
and takes the first Frontier member appearing in it.

ADR-0001 made Packs generated, which turned that into a live problem. A
generated Pack that ships no Stages hits the fallback —
`frontierNames.sorted().first!` — and the app's single most important
recommendation silently becomes alphabetical. A reader is told to learn "Agent
Memory" before "Attention" before "Embeddings", with no signal that ordering has
stopped meaning anything.

**Decision:** Reading order stays authored where a Pack states one, and falls
back to a **topological sort of the Dependency graph** where it does not.
Alphabetical ordering is removed as a fallback. Stages remain part of the Pack
file format.

## Considered options

- **Keep authored Stages as the only order.** The faithful port, and it keeps
  the fallback alphabetical. Rejected because it makes the quality of every
  generated Pack's core recommendation depend on the generator remembering to
  emit Stages, and fails silently when it doesn't — the reader sees a confident
  recommendation, not a degraded one.
- **Derive the order from the Dependency DAG entirely**, demoting Stages to
  presentation for the "You are here" ladder. Genuinely tempting: every valid
  Pack gets a defensible order for nothing, since `PackValidator` already
  rejects cyclic Dependency graphs, so a topological sort always exists.
  Rejected because a topological sort is only as opinionated as the Dependency
  graph, and many valid orders satisfy it — a Pack author who deliberately
  front-loads the cheap wins before the hard foundations has no way to say so.
  That editorial judgement is most of what makes a hand-authored Pack worth
  more than a generated one.

## Consequences

`PackFile` carries `stages`, so a Pack author or generator may state a path, and
`PackValidator` already rejects a Stage naming an unknown Concept. Nothing
forces a Pack to carry Stages, and that is the point: the derived order makes
them optional rather than load-bearing.

The tie-break is a second consumer of the Dependency graph's acyclicity, which
until now only mattered because a cycle means the Frontier never advances.
Topological sort makes the guarantee `PackValidator.checkAcyclic` provides
load-bearing for recommendations too.

`pathOrder` is currently `stages + sideQuestConcepts`, and `PackFile` has no
`sideQuestConcepts` field — only `specialtyCluster`. Installing a Pack must
therefore reconstruct that tail from the specialty Cluster's membership, or drop
the distinction. `ClusterDetailView` builds the same `pathOrder` expression
independently, so whatever replaces it needs one home rather than two.
