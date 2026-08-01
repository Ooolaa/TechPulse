# Hot Topics are observed from Sources, not curated or fetched from a platform

The 🔥 lane runs off `KnowledgePack.hotTopicAliases`, a hardcoded list of terms
matched against article text. ADR-0001 made Packs user-generated, and `PackFile`
has no field for aliases — so under that decision the hot-topics lane simply
dies for every Pack but the built-in one.

**Decision:** Hot Topics are **inferred** from term frequency across recent
articles drawn from whatever Sources the user has, rather than declared by a
human or fetched from any platform's API. A term rising across your own reading
is what "hot" means. Terms that are hot but match no Concept become candidate
Concepts.

## Considered options

- **Add an aliases field to `PackFile`.** Rejected: it makes every generated
  Pack's radar only as fresh as its generation date, and makes someone
  responsible for maintaining a list per career, forever.
- **Integrate Reddit's JSON API for real scores and comment counts.** Rejected,
  and worth recording as an explicit no. It would break the Source definition —
  *a Source is a subscription, not a publisher; the app is indifferent to what
  kind of thing is on the other end* — in exchange for a signal already
  obtainable without it.

## Why no Reddit-specific code is needed

Reddit serves vote-sorted feeds as ordinary RSS:
`https://www.reddit.com/r/MachineLearning/top/.rss?t=week` returns 25 entries
over plain HTTP. Popularity ordering is therefore a property of the *URL the
user subscribed to*, not something the app computes about a platform it knows
about. Reddit improves the signal precisely because its feeds are already
vote-sorted, while remaining just another Source.

## Consequences

Reddit throttles aggressively: a back-to-back fetch of a second subreddit
returned **HTTP 429** during this investigation, with the existing custom
User-Agent set. `FeedSyncService` fetches every Source concurrently in a task
group and swallows failures with `try?`, so several subreddits will silently
yield nothing. Per-host request pacing and visible Source health (ROADMAP item
12) become prerequisites rather than nice-to-haves.

Intake is capped at 30/day sorted newest-first, so a "top this week" entry
carrying a six-day-old timestamp loses to same-day arXiv papers by construction.
Whatever surfaces Hot Topics cannot rely on those articles winning the newest
-first race.
