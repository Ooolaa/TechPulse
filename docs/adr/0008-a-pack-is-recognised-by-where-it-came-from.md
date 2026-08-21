# A Pack is recognised by where it came from, not by what it is called

A Pack's `field` is the only thing naming it in the file format — `PackFile`
carries a format version, a field, and the map; no identifier. So when the app
needed to ask "is this stored record that Pack?", the field was the only answer
available, and every path that asked used it: the launch refresh that delivers a
new version of a built-in Pack, the rebuild after a lost record (#37), the sweep
that supersedes an earlier record of the same Pack (#18).

A field is prose. It is written by the Pack's author, shown to the reader, and
rewriting one is a normal thing to want to do. Matching on it meant that the day
anyone did, **no launch would recognise that reader's record again** — the guard
fell through forever, the version was never recorded, and built-in Pack updates
stopped silently and permanently (#19). The same assumption made a second claim
the code had generalised without noticing: that a field names one Pack. It does
not. Since #18 the store deliberately keeps one record per (field, origin) pair,
so a reader with both a built-in "Security Engineering" and a Pack of their own
by that name has two records — and recovery reactivated whichever was installed
later (#39).

**Decision:** a stored Pack record is recognised by where it came from.

- A **built-in Pack** is matched by the **file name** it shipped under. The app
  controls that name; the reader never sees it. It is stored on the record at
  install, so the field it was installed under is free to change afterwards.
- Any record is otherwise matched by the **(field, origin) pair**, which is the
  identity #18 already made the store keep one of.
- The **field alone** remains the last thing tried, so a record written before
  either was stored is still found rather than rebuilt narrower.

The three run narrowest first, and `installedAt` breaks a tie only *inside*
whichever answers. It used to be the whole match.

## Considered options

- **Give the Pack file an identifier.** An `id` in `PackFile`, authored
  alongside the field, would identify every Pack rather than only the built-in
  ones. Rejected: a Pack file is authored by anyone, so the id is exactly as
  trustworthy as whoever wrote it — two people exporting the same Pack produce
  two ids, one person copying a file produces two Packs claiming one id, and the
  app would be trusting a stranger's string to decide which of the reader's maps
  to overwrite. The file name works precisely because it is *not* in the file:
  it is the app's own name for a Pack the app itself ships. It also breaks the
  format, and `formatVersion` is a hard break — older builds reject new files.
- **Keep matching on field, and forbid renaming one.** Free, and honest about
  what the code did. Rejected because it makes a reader-visible string
  load-bearing forever: every future edit to a Pack's copy becomes a migration
  risk, and nothing in the codebase could enforce it. A rule that only exists in
  a comment is one release away from being broken by someone reading the Pack
  file as copy — which is what it is.
- **Match on the Concepts.** A record whose Concept set overlaps a shipped
  Pack's is probably that Pack, which would recognise even a record written
  before file names *and* renamed in the same build. Rejected: a wrong match
  installs a Pack over the reader's map and retires the one they were on. The
  failure this ADR exists to prevent is silent and permanent, but not
  destructive; this one is destructive. Not updating is a better failure than
  updating into the wrong map.

## Consequences

**A built-in Pack's `field` must not be rewritten in the same build that first
stores file names.** Records written by earlier builds carry no file name, so
each gets exactly one field-based match to be adopted onto its file — spent on
the first launch after this ships, whether or not anything installs. A rename
landing in that same build tries that single match against a field that has
already moved, and strands exactly the reader this decision protects. One
shipped build apart is enough. The rule lives on `PackMigration`'s adoption step,
which is the only place it can be acted on.

**An unrecorded origin is indistinguishable from an imported one.** The identity
that outlives the store keeps two strings, and a missing origin reads as
`.imported`. So a reader from before origins were remembered, who has *both*
records, is read as having been on their own Pack — a guess, but a settled one
rather than whichever record is newer. Distinguishing them would mean the
remembered origin becoming optional and the fallback moving to each point of use.

**A built-in whose *file* is renamed falls back to the field.** Renaming a Pack
file is a code change, not the reader-visible rewrite this guards against, so
the fallback costs nothing — but a Pack the app can still recognise should be
recognised. Two built-in Packs covering one field would break that fallback,
which is why a test asserts they never do.

**Superseding an earlier record follows the same rule.** #18's sweep matches a
built-in by file name too; otherwise a renamed Pack would leave the reader
holding one record per name it had ever been given.
