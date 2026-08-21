# TechPulse

A habit-driven reading app. You read a little every day from sources you choose;
what you read lights up a map of the field you're learning.

## Language

**Concept**:
A single idea worth learning, and one dot on the map. The unit everything else
is measured against.
_Avoid_: node, dot, note, topic, tag, skill

**Pack**:
A field's worth of Concepts, their Clusters, their Dependencies and a suggested
set of Sources — the map before you've read anything. A Pack is data, not code:
it can be authored, generated, or installed. The AI Engineer pack is the
flagship, not the only one.
_Avoid_: curriculum, syllabus, course, career

**Field**:
The subject a Pack covers, named by its author and shown to the reader. Prose,
not a name the app relies on: two Packs may cover the same field — one the
reader was given and one that ships with the app, say — and a Pack may be
renamed between versions of itself.
_Avoid_: domain, subject, topic, area, pack name

**Origin**:
Where a Pack came from: the app itself, a file the reader was given, or
generation. Reader-visible, and what tells two Packs apart when they cover the
same field.
_Avoid_: source (a Source is a place reading arrives from), kind, provenance

**Built-in Pack**:
A Pack that travels inside the app, read and checked on the same path as one
the reader was given. The app keeps its file, so it is the only kind of Pack a
new version of the app can update, and the only kind it can rebuild from
nothing.
_Avoid_: default pack, bundled pack, stock pack, preset

**Flagship**:
The one built-in Pack a reader lands on when nothing else says which Pack is
theirs — the AI Engineer map the app shipped with. Where a reader ends up when
the answer was lost, not a Pack the app prefers.
_Avoid_: default pack, main pack, primary pack, starter pack

**Active Pack**:
The one installed Pack the app is currently a map of. Installing another
retires the previous one without taking its Concepts away — what you learned is
yours, not the Pack's, so a retired Pack's Concepts keep their Mastery and
history whether or not the new Pack still contains them.
_Avoid_: current pack, selected pack, installed pack (ambiguous — several may
be installed, one is active)

**Cluster**:
A named group of Concepts within a Pack ("Foundations", "Agents"), and the unit
progress is reported against.
_Avoid_: category, section, topic, module

**Dependency**:
A directed edge asserting that one Concept should be learned before another.
Authored as part of a Pack.
_Avoid_: prerequisite edge, arrow, blocker

**Semantic Link**:
An undirected edge between two Concepts that mean related things, derived from
the Concepts themselves rather than from anything you did. Present from the
moment a Pack is installed.
_Avoid_: similarity edge, embedding link

**Co-read Link**:
An undirected edge between two Concepts you have met together in the same
reading. Observed, never authored — a Co-read Link records what you actually
read, a Dependency records what someone claims is true.
_Avoid_: co-occurrence, relation, association, edge (ambiguous — name the kind)

**Lit**:
The state of a Concept you have engaged with at all, as opposed to one still
untouched. Lighting the map is the reward loop.
_Avoid_: unlocked, completed, visited, seen

**Mastery**:
How well a Concept is held, from newly-seen to known. Grows by reading and
quizzing, fades without review.
_Avoid_: score, level, XP, progress

**Frontier**:
The set of unlit Concepts whose Dependencies are all Lit — what you're ready to
learn right now.
_Avoid_: available, unlocked, ready set

**Next Dot**:
The single Concept recommended from the Frontier, picked by Stage order so the
recommendation follows the path the Pack's author intended rather than an
arbitrary ready Concept. The app makes one recommendation, not a list.
_Avoid_: suggestion, recommendation, up next

**Side Quest**:
A Concept in the Pack's specialty Cluster — the optional lane running alongside
the staged path, reported on separately so progress through it never reads as
falling behind on the main one. A Pack need not have one.
_Avoid_: bonus, extra, optional track

**Stage**:
A named step in a Pack's reading order, grouping the Concepts its author thinks
should be met together. Authored, unlike the Frontier it filters, and it does
two jobs: it draws the "You are here" ladder, and its order is what reduces a
Frontier of several ready Concepts to one Next Dot. A Pack with no Stages still
has a Frontier; it just has no opinion about which part of it to read first.
_Avoid_: level, chapter, milestone, phase

**Hot Topic**:
A term rising in frequency across your recent reading. Observed from your own
Sources, never declared by hand — what the field is talking about now, as
opposed to what a Pack author thought mattered when they wrote it.
_Avoid_: trending, buzzword, radar, hype

**Source**:
A place reading arrives from, chosen by the user. A Source is a subscription,
not a publisher — the app is indifferent to what kind of thing is on the other
end.
_Avoid_: feed, channel, subscription, publisher

**Reading Intention**:
The user's own stated plan for when reading happens — a time, and the existing
routine it follows. Stated by the reader rather than inferred from their
behaviour, changeable afterwards, and the thing a reminder is derived from. The
notification itself is a **reminder** — that word names what arrives, never the
intention it came from.
_Avoid_: reminder, schedule, goal, notification setting

**Streak**:
The consecutive days on which reading happened, counted back from the most
recent one. Survives a day not yet extended; only a fully missed day breaks it.
_Avoid_: chain, run, combo

**Egress**:
Everything the app sends off the device, as a closed and enumerated list. The
point of the term is that the list is complete and checkable: a feature that adds
to it is changing the product's central promise, not adding a detail. Work done
on the device — however much of your reading it touches — is not Egress, which is
what makes the promise sayable at all. Described the same way wherever it is
described: **no passage of what you are reading leaves, and a word you select is
the most of an article that ever does.**
_Avoid_: telemetry, analytics, tracking, upload, data collection
