---
description: Run one TechPulse dev cycle — test, exercise, groom, implement, review. Self-paced; use with /loop for repeats.
---

Run one full cycle of the TechPulse development loop, then stop and report.

Each stage hands its output to the next. A stage that finds nothing to do says
so in one line and the cycle moves on — an empty stage is not a failure.

## The cycle

1. **Verify.** `tp-test-runner`. If the suite is at its known simulator floor
   (14 failures, `docs/agents/test-baseline.md`), it's green — continue. If there
   are real regressions, **stop the cycle here** and report them; a red suite
   makes everything downstream untrustworthy.

2. **Exercise.** `tp-journey-driver` on the journeys touching whatever changed
   most recently, light and dark. All eight only when the last cycle landed
   something broad, or nothing has been walked in a while.

3. **Groom.** `tp-issue-groomer`. File anything stages 1–2 turned up — excluding
   the embedding floor, which is declared and not a defect. Triage what's
   untriaged and name the next `ready-for-agent` issue.

4. **Implement.** `tp-implementer` on that one issue, to a PR. One issue per
   cycle. If nothing is genuinely `ready-for-agent`, skip this stage and say
   what the backlog needs instead — usually a specific question answered.

5. **Review.** `tp-reviewer` on the PR stage 4 opened. Report findings; don't
   merge. Merging stays a human decision.

## Rules

- **Never merge, never force-push, never rewrite published history.**
- One issue per cycle. Throughput comes from repeating the loop, not from
  widening it — five half-finished branches are worse than one merged PR.
- Don't chase the 14 simulator embedding failures. They are the floor.
- If two stages disagree — a test says green and a journey says broken — report
  both rather than picking. That disagreement is the most interesting output the
  loop produces.
- Stop and ask when a decision is architectural. An ADR is written by a human.

## Report

Close with five lines, one per stage: what it found, what it did. Then one line
on what the next cycle should pick up. If the cycle produced nothing — suite at
baseline, backlog empty of ready work — say that plainly; a quiet cycle is a
real result and padding it helps nobody.
