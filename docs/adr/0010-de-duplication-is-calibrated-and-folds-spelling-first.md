# De-duplication is calibrated, and folds spelling before it asks about meaning

ADR-0002 gave the map three kinds of edge and left a consequence open: near-
duplicate Concepts gain strong Semantic Links to each other and clutter the map,
and de-duplication was not catching them. #11 removed the 500-Concept ceiling
that switched merging off on exactly the maps that needed it. What was left was
the threshold, `ConceptIndex.sameIdeaDistance`, at 0.25.

Measured, 0.25 admits nothing. Not a plural (`world model` ~ `world models` is
0.449), and not "LLM" ≈ "Large Language Models" (1.26), which the doc comment on
`findOrCreateConcept` advertised from the day it was written. Matching by
meaning was doing nothing matching by name did not already do, at every map size
(#41).

Widening it by eye is worse than leaving it narrow. A merge is destructive: the
incoming Concept is never created, so Mastery, Lit state and `LearningEvent`
history consolidate onto whichever name arrived first. #11's own first draft
used a metric eight times too permissive and merged "supervised learning" into
"unsupervised learning".

**Decision:** the threshold is **0.50**, derived the way `SemanticLinker`'s
relatedness floor was — from measurements over real Concept names, written down
beside the constant — and `ConceptIndex.match` **folds spelling before it asks
about meaning**, using `ConceptMatch.fold`, the fold Explain already uses.

The measurement is every pair of the 120 Concept names the two built-in Packs
contain — 7,140 of them — against restatements of those same names written the
way an Article's analysis says them. The two halves split the work, and only
what is left to the distance decides where the distance goes:

| what is left for the distance to merge | measured |
| --- | --- |
| "&" spelled "and": `Identity & Access Management` | 0.24–0.30 |
| one letter of spelling: `Defence`, `Modelling`, `Quantisation` | 0.33–0.38 |
| an article in front: `The Transformer Architecture` | 0.392 |
| **nothing the fold does not already have** | **0.39–0.62** |
| the closest two distinct names ship (`Vision Language Models` ~ `Reasoning Models`) | 0.620 |
| `Batch Normalization` ~ `Layer Normalization` | 0.635 |
| `Supervised Learning` ~ `Unsupervised Learning` | 0.691 |

0.50 is the middle of that empty stretch — 0.11 above the widest restatement the
distance carries, 0.12 below the closest pair of distinct names either Pack
contains. The margins are not equally valuable, which is why the empty stretch
being wide enough to hold both matters: being wrong on the low side costs a
reader a duplicate dot, and on the high side their history.

The fold takes the rest, and it is a band no threshold could have had: plurals
and separators from 0.33 to 0.57, including a plural of a *one-word* name
(`Benchmarks` ~ `Benchmark`, 0.67; `Guardrails` ~ `Guardrail`, 0.75) which sits
among the distinct pairs, because one word of a one-word name is the whole of
its meaning.

## Considered options

- **Widen the threshold far enough to catch one-word plurals.** It would have
  to reach past 0.75, and two distinct names the flagship ships are 0.62 apart.
  Rejected: that is not a wider threshold, it is merging the Pack into itself.
- **Fold spelling and leave the threshold at 0.25.** Catches the plurals and
  the hyphens, and nothing else — an "&" spelled "and", `Defence` for `Defense`,
  and a Concept restated in different words all still make a second dot.
  Rejected: the measurement says the safe band is real and 0.25 is not near it.
- **0.55, the middle of the stretch with nothing measured in it *at all*.**
  Rejected once the two halves were separated: every restatement between 0.39
  and 0.57 is one the fold already merges, so the extra 0.05 buys nothing that
  was measured and spends margin on the destructive side.
- **Keep the fold out of the dedupe path, as ADR-0007 left it.** That ADR
  declined to apply the fold here on the grounds that widening dedupe was a
  separate decision about Pack installation. It is; this is that decision, taken
  with the measurements ADR-0007 did not have.
- **A stemmer, or a synonym list, for abbreviations.** Rejected as out of reach
  of this instrument rather than out of scope for this map: `rag` ~ `retrieval
  augmented generation` is 1.32, further apart than two unrelated Concepts, so
  no threshold on a sentence embedding can have it. Catching abbreviations needs
  something that is not a sentence embedding, and is its own decision.

## Consequences

**The limits are stated, not implied.** An abbreviation still makes a second dot
on the map — `LLM` beside `Large Language Models` — and so does one letter
inside a one-word name (`Tokenisation`, 0.578, which folds differently too).
Both are written beside the constant and asserted in `ConceptDedupeTests`, so
the next person to read the threshold reads what it does not do.

**A Pack whose own names merge into each other is now a test failure.**
`builtinPacksHoldNoPairInsideTheThreshold` measures every pair of names both
built-in Packs contain, on both halves of the match. It is the calibration
itself, kept runnable: a Pack that adds a name 0.45 from one already there, or
one that folds onto it, fails the suite rather than losing a reader's history in
the field.

**Hot Topics suppresses more, and the terms it lets through are measured too.**
`HotTopics.candidates` asks the same question with the same constant, and now
the same fold. Before the fold, "Benchmarks" could be offered to a map holding
"Benchmark" and adopting it would merge straight back into the Concept the
reader had. What the widening might have cost is the growth the feature exists
to catch, so that side is a test as well:
`realEmbeddingStillOffersWhatIsGenuinelyNew` runs rising terms against the whole
flagship Pack with the model that ships, "small models" among them — the nearest
any measured term came to a Concept name, at 0.570, and still offered.

**ADR-0002's open half is closed.** Its consequence about the de-duplication
cliff is amended to point here.

**ADR-0007's boundary moved, and only for dedupe.** Explain still matches the
map on spelling and not on meaning: what changed is what `findOrCreateConcept`
merges *after* a generation, not what a selection sends. The most that leaves
the device is what ADR-0006 enumerated and what ADR-0007 narrowed — a selected
word the map has no name and no fold for, on the opt-in path.
