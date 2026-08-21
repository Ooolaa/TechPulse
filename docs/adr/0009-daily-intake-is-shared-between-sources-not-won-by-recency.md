# Daily intake is shared between Sources, not won by recency

`FeedSyncService.syncAll` pools every enabled Source's items into one list,
sorts it `publishedAt` newest-first, and keeps the first `dailyIntakeLimit`
(30). The comment says this "keeps the best (freshest) 30 rather than whichever
feed happened to come first", and as fairness between Sources arriving in an
arbitrary order, it is right.

It is wrong about what "best" means, and ADR-0003 predicted exactly how. A
Source is a subscription, and *what a Source is ordered by is part of what you
subscribed to* — so `reddit.com/r/MachineLearning/top/.rss?t=week` is how
community attention reaches a reader without the app learning that popularity
exists. But a "top this week" entry carries its original post date, up to six
days old. The three arXiv feeds alone contribute up to `perFeedLimit` (30) items
each, all same-day. Sorted globally by date, the week's best post loses to
ninety same-day papers **by construction**, every day, forever.
`newSourceAllowance` carries it through day one and then it goes dark.

So the recency sort silently makes every Source chronological, whatever the
reader subscribed to. It does not merely disadvantage a popularity-ranked
Source; it deletes the only property that made it worth adding.

**Decision:** intake is allocated **round-robin across Sources** — each Source
offers its own newest-first, and the cap is spent one item per Source per turn
until exhausted. Global recency ordering is removed as the allocator.

## Considered options

- **Reserve a minimum of N slots per Source, then fill the remainder
  newest-first** (ROADMAP item 12's proposal). Rejected on arithmetic: the
  flagship Pack ships 13 Sources and the cap is 30, so N=2 spends 28 of 30
  before the newest-first fill begins. It is round-robin with a tunable constant
  bolted on, and the constant has no defensible value at this cap.
- **Exempt popularity-ranked Sources from the recency sort.** Rejected, and
  worth recording as an explicit no for the same reason ADR-0003 refused
  Reddit's JSON API: the app would have to know which Sources are
  popularity-ranked, which breaks *a Source is a subscription, not a publisher —
  the app is indifferent to what kind of thing is on the other end*. The fix has
  to work without the app ever classifying a Source.
- **Raise `dailyIntakeLimit`.** Rejected: the cap is a habit decision, not a
  technical one — an overflowing feed kills the habit, which is why 30 was
  chosen. Raising it to make room for one Source trades the product's core
  premise for a scheduling bug.

## Consequences

**Reading gets broader and shallower, and this is a real cost.** At 13 Sources
and a cap of 30, each Source contributes roughly two articles a day. arXiv
currently can take a far larger share on a heavy publishing day and will stop
doing so. A reader who valued the app as an arXiv firehose will notice. That
trade was accepted deliberately: the map is fed by breadth across a field, and
the 🔥 lane's whole premise is observing what *your Sources* are saying, which a
single dominant Source quietly turns into what one Source is saying.

Round-robin needs no per-Source constant, so nothing here binds to how many
Sources a Pack ships. A Pack with three Sources and a Pack with thirty both get
a defensible allocation.

The 🔥 lane changes character as a result, without `HotTopics` changing at all.
Its scoring already asks which terms distinguish a recent window from an older
one; feeding it a popularity-ranked Source means community attention now
influences that window. No code in `HotTopics` knows this happened, which is the
point.

This decision is a prerequisite for the popularity-ranked Source, not an
independent improvement — shipping the Source without it changes nothing
observable, and shipping it alone changes reading for a benefit not yet visible.
They belong in the same release.
