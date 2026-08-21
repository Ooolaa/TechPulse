# Explain matches the map on spelling, not on meaning

ADR-0006 accepts a quality cost — a word ambiguous *inside* the reader's own
field, "bias" statistically against "bias" in fairness, is no longer separable
once the excerpt stops being sent — and rests that acceptance on a mitigation:
the affected words are "disproportionately words already on the map, which never
reach a model at all".

The mitigation was narrower than the sentence. `ArticleView.explain` matched a
Concept by name, case-insensitively and nothing else, so "LoRA" opened the
Concept named `LoRA` while **"LoRAs", "low-rank-adaptation" and "RAG systems" each fell
through to a generation** — on the opt-in path, one more selected word leaving
the device. The embedding match that would have caught the first two lives in
`KnowledgeEngine.findOrCreateConcept`, which runs *after* generating: it dedupes
the result, so the reader still lands on the right Concept and no twin is made,
but the request has already happened (#31).

**Decision:** the match folds **spelling** before comparing — case, separators
(hyphens, dashes, underscores) and English plurals — and stops there. "LoRAs"
finds `LoRA`; "low-rank-adaptation" finds `Low-Rank Adaptation`. A name spelled
exactly as selected still wins over one that merely folds the same, so the fold
only ever *widens* what matches: no selection that opened a Concept before opens
a different one now.

It does **not** fold meaning. A synonym ("retrieval augmented generation" for
`RAG`) and a phrase around a word on the map ("RAG systems") still reach a
model. That boundary is `ConceptMatch`, pure and unit-tested on both sides —
which words are answered offline, and which become `Egress`.

The decision `ArticleView.explain` makes moved out of the view with it, into
`ExplainRoute`: map first, model second, with `canDeepen` asked *after* the map,
so a word the reader already has is explained on hardware that can explain
nothing. #29's own review found tested builders behind an untested call site
(`1f8334e`); this call site is where the ADR-0006 claim actually lives, so it is
tested rather than restated in a `first(where:)`.

## Considered options

- **Reorder: embedding match before generating.** Catches synonyms too, which is
  strictly more of what the mitigation claims. Rejected on two counts. It puts
  an `NLEmbedding` pass on every selection, work the exact-name path does not
  do. And the similarity threshold that is safe for *deduping a result the model
  already returned* is not the same threshold as *deciding not to ask*: a false
  positive there shows the reader a definition of a Concept they did not tap,
  offline, with nothing to signal that a substitution happened. The distance was
  chosen for the first job. Buying synonym coverage with a silent wrong answer
  is a bad trade in a reading app.

  **Correction (2026-08-21):** this bullet read "The current 0.25 distance was
  chosen for the first job". The distance is 0.50 since ADR-0010 calibrated it,
  and the reasoning is unchanged — a threshold safe for deduping a result the
  model already returned is still not the one for deciding not to ask (#41).
- **Leave the code, narrow the ADR.** Honest, and cheap: ADR-0006's sentence
  would become "words already on the map under the name the Pack gave them",
  which is true of the code as it stood. Rejected because the shape it concedes
  is the common one — readers select words as they appear in prose, and prose
  pluralises. Conceding "LoRAs" costs a real request to keep a real one-line
  fold out of the codebase.
- **Fold the head noun off a phrase** ("RAG systems" → `RAG`). Rejected: it is
  the first fold that is a guess about meaning rather than about spelling, and
  it fails in the direction that matters — "vector database" is not "database".

## Consequences

**ADR-0006's mitigation sentence now says what the code guarantees.** It names
the fold and, more importantly, names what the fold does not cover. The reason
this ADR exists rather than a commit message is that the sentence was
load-bearing: a consequence accepted on a mitigation is only as accepted as the
mitigation is true.

**`Egress` shrinks, and the list is unchanged.** Nothing new is sent; strictly
fewer selections reach `api.anthropic.com` on the opt-in path. `PRIVACY.md` says
so from the reader's side — a word already on your map is answered from your map
and sends nothing.

**Over-folding is symmetric, which bounds its cost.** The fold runs on both
sides of the comparison, so folding too hard produces a wrong match only where
two *Concept names* fold together — "Agent" and "Agents" as separate Concepts,
which is a map that would already confuse its reader. Folding too gently costs a model
call that was going to be paid anyway. That asymmetry is why a rough plural rule
is acceptable here and a similarity threshold is not.

**`findOrCreateConcept` is deliberately untouched.** The fold is not applied to
the dedupe path: the two never run on the same term (Explain returns before
generating when the map already has the word), and the embedding match there is
doing a job it is correctly threshold-tuned for. Widening dedupe is a separate
decision about Pack installation, not about what leaves the device.

**Amended (2026-08-21):** that decision has since been taken —
[ADR-0010](0010-de-duplication-is-calibrated-and-folds-spelling-first.md)
applies this fold to `ConceptIndex.match` as well, and moves the threshold to
0.50. The clause about being "correctly threshold-tuned" is the part that did
not survive a measurement: at 0.25 the embedding match merged nothing a name
match did not already merge (#41). Explain routes the same selections the same
way it did before, and the most that leaves the device is what this ADR left —
a selected word the map has no name and no fold for, on the opt-in path.
