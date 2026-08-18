# Explain disambiguates from your Pack, not from the article

Explaining a word the reader selected needs some way to tell which sense is
meant — "transformer" in an AI article is not the one in a substation. The
feature answered that by sending the word plus a ±220-character window of the
surrounding article prose, and on hardware without Apple Intelligence that window
went to Anthropic. Three documents said it never did: `README.md`, `ROADMAP.md`'s
standing constraints, and the 2026-08-02 `DEVLOG.md` entry that wrote the other
two. All three were reasoning about **Go deeper**, where the claim is true, and
none was re-checked when Explain began using the same client (#29).

**Decision:** the opt-in path sends the selected term, the Active Pack's **field**,
and its **Cluster** names. No article text. The reader's own map supplies the
disambiguation the excerpt used to: "someone studying AI engineering asked what
LoRA means" picks the right sense of most words, and the model never sees a
document the reader was reading.

The **on-device path keeps the excerpt**, deliberately. Nothing leaves the device
there, so the better signal is free. The two paths therefore build different
prompts on purpose — this is not an inconsistency to tidy up.

## Considered options

- **Send the term alone.** The safest payload and the weakest answer: nothing
  disambiguates, so exactly the words worth explaining — the overloaded ones —
  get explained wrong. Rejected because it degrades the feature at its centre
  rather than at its edge.
- **Keep the excerpt and disclose it.** Honest, and it costs the promise. "Your
  reading stays on your phone" would acquire a caveat that has to be repeated
  everywhere the promise appears, which is the condition under which the three
  documents drifted in the first place. A claim with an exception is a claim
  somebody will restate without the exception.
- **Ask the reader's consent at the point of use.** Also honest, and it puts a
  privacy decision in front of someone who is mid-sentence in an article. The one
  thing a reading app should not do is interrupt reading to negotiate.
- **Drop Explain on hardware without Apple Intelligence.** The cleanest privacy
  answer and rejected on `ROADMAP.md`'s fallback-first constraint: the reference
  device is an iPhone 14 Pro with no Apple Intelligence, so this deletes the
  feature on the device the app is actually read on. That constraint is *why* the
  opt-in path exists at all.

## Consequences

**Where two standing constraints conflict, fallback-first wins.** `ROADMAP.md`
lists fallback-first and the privacy stance side by side as absolutes, which is
how they came to contradict each other unnoticed. The rule this ADR sets: a
feature keeps working on hardware without Apple Intelligence, and the privacy
stance is honoured by changing **what is sent**, not by removing the feature.
`ROADMAP.md` says so now rather than leaving it to be rediscovered.

**A cost, taken knowingly.** A word ambiguous *within* the reader's own field —
"bias" in the statistical sense against the fairness sense — is no longer
separable, where the sentence would have separated it. Accepted: the field
resolves the common collisions, and the sentence-level cases are
disproportionately words already on the map, which never reach a model at all
(`ArticleView.explain` matches an existing Concept first and returns).

**The claim becomes checkable.** The reason this survived weeks is that nothing
could assert what leaves the device: `AnthropicClient()` is constructed inline
inside `IntelligenceService`, so there is no seam and no test. Prompt
construction moves into pure functions over the term and the Pack, unit-tested,
so a test goes red the moment article text re-enters the opt-in prompt. The
client is deliberately **not** made injectable — transport is not what anyone got
wrong, and a seam bought for a hypothetical is one more thing to maintain.

**`Egress` is now a term.** The stance had no name, so "on-device by default",
"nothing leaves the phone", "concept name/definition only" and "opt-in exception"
were four phrasings nobody could check against one another. `CONTEXT.md` defines
it as the closed, enumerated list of what leaves the device, and `PRIVACY.md`
renders that list. A feature that adds to it is changing the product's central
promise, not adding a detail.

**arXiv stays, and joins the list.** `TopicSearchService` sends a Concept name to
`export.arxiv.org`, undisclosed until the same audit. It is kept: a search term
reaching a search API is the feature working, there is no less-revealing payload,
and proxying it would require the first-party server the product does not have.
