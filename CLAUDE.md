## Agent skills

### Issue tracker

Issues live as GitHub issues in this repo's remote, managed with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, used verbatim as label strings. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Test baseline

What a green run looks like, how to read an `.xcresult`, and why a cluster of
embedding failures means a cold simulator rather than a regression — it clears
once `NLEmbedding`'s model downloads. See `docs/agents/test-baseline.md`.

### Agents and the dev loop

Five agents in `.claude/agents/` cover the cycle — `tp-test-runner`,
`tp-journey-driver`, `tp-issue-groomer`, `tp-implementer`, `tp-reviewer`.
`/tp-loop` runs one pass through all five. These are agents; the five labels in
`docs/agents/triage-labels.md` are issue states, and the two are unrelated.
