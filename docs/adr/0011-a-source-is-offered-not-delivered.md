# A Source is offered, not delivered

Two mechanisms put Sources in front of a reader, and they disagreed about
consent.

`PackSourceOffer` **offered**. Its sheet said so in as many words — *"Nothing is
subscribed until you say so"* — and `PackInstaller` deliberately subscribed to
nothing, leaving a Pack's suggestions on the record for the app to put to the
reader.

`SeedData.seedIfNeeded` **subscribed**. It ran from `TechPulseApp` on every
launch and inserted any entry of `SeedData.defaultSources` the store did not
already have, so that *"app updates deliver new feeds to existing installs"*.

The seeder was the one that actually reached anybody. The offer fires when a
reader installs a Pack **from the library by hand**, not on the launch-time
reinstall a `builtinPackVersion` bump triggers — so a Source added to a shipped
Pack reached nobody through the Pack file, and everybody through the array
(#46).

That cost three things at once.

- A Source added to `defaultSources` **arrived in a reader's Settings without
  their ever being asked**.
- Because `PackSourceOffer.pending` filters out URLs already subscribed, the
  arrival **suppressed the offer for that Source permanently**. The reader could
  never be asked, because they already had it. The consent gap closed itself.
- `defaultSources` was the **AI** list and `seedIfNeeded` was not conditioned on
  the Active Pack, so a reader who chose Security Engineering still received
  arXiv cs.AI, OpenAI News and r/kaggle. The Pack chooser let a reader pick a
  field; the seeder ignored the choice.

**Decision:** a Source is offered. The Pack a reader is on is what suggests, and
the reader is what subscribes.

- **The Pack file is the only list anything reads.** `SeedData.defaultSources`
  is gone; suggestions are read off `ActivePack.inUse.suggestedSources` — the
  installed record — so a Security Engineering reader is asked about Security
  Engineering. The *text* of the flagship's list still exists in a second place,
  as a test fixture; what ended is a second place that could deliver it.
- **The first launch of an empty store subscribes what the Active Pack
  suggests.** This is the one exception, and it is bounded by having nothing to
  read: an offer needs a Feed to be weighed against, and an empty app is a worse
  first impression than a Source too many. Settings is one tap away.
- **Every launch after that subscribes nothing.** A Source arriving in a new
  version of a Pack becomes a **standing offer**, surfaced as a row in Settings,
  and waits there until the reader answers it.
- **A suggestion turned down is not raised again.** Declines are recorded, and
  only the standing offer consults that record.

## Considered options

- **Keep seeding, but scope it to the Active Pack.** Free, and it fixes the
  sharpest edge: the Security Engineering reader stops receiving AI Sources.
  Rejected as a stopping point rather than as a step — it leaves the app
  subscribing readers to Sources they were never asked about, now merely pointed
  at the right Pack. The glossary says a Source is "chosen by the user", and
  this keeps that false.
- **Offer everything, including the first launch.** The strictest reading, and
  the one with no exception to explain. Rejected: a new install would open on an
  empty Feed behind a sheet the reader has no way to evaluate — they have not
  seen the app yet, and the Sources are the app. The consent this protects is
  worth less than the first run it costs, and the reader can turn any of them
  off in the same screen the offer would have sent them to.
- **Surface the offer at launch, as a sheet.** More likely to be seen than a
  Settings row. Rejected: launch is the moment the reader came to read, and a
  modal in front of the Feed to ask about a Source they did not know they wanted
  is a worse trade than a row that waits. A row also survives being ignored,
  which a sheet does not.
- **Record declines in the store rather than `UserDefaults`.** Rejected: a
  decline is about what the reader has been *asked*, not about what their map
  contains, and it has to outlive a Pack being reinstalled over the top — which
  is the same reason `ActivePackIdentity` lives there.

## Consequences

**A Source added to a Pack now reaches existing readers slowly, or not at all.**
That is the point, but it is a real cost: a suggestion that would once have
appeared in every install on the next launch now waits behind a row that a
reader may never tap. Anything that *must* reach a reader is not a suggestion
and cannot be shipped as one.

**The offer is only as visible as the Settings row.** Nothing else surfaces it —
no badge, no launch prompt. If a Pack ever ships a suggestion that matters, this
is the constraint to revisit first, and the ADR to supersede.

**A decline is close to permanent.** The only way back is installing that Pack
from the library, which re-offers everything, because choosing a Pack by hand is
a reader asking to see its Sources. There is deliberately no "show me what I
turned down" screen — turning something down should not create a second list to
maintain. A reader who wants a specific Source back can also add it themselves.

**Sources a reader already received unasked are left alone.** A Security
Engineering reader who was handed the flagship's Sources before this keeps them:
Settings can only toggle a Source, not delete one, and deleting subscriptions
out from under a reader — along with the Articles that point at them — is a
worse thing to do than the one being corrected. They stop *arriving*; the ones
that arrived stay, and can be switched off.

**`KnowledgePack.suggestedSources` still exists, and delivers nothing.** The
compiled AI list survives as the fixture `BuiltinPacksTests` compares
`ai-engineer.json` against, next to `concepts` and `stages`, so the conversion
cannot silently drop a Source. What made #46 subtle was not that the list was
duplicated — it was that one copy was *also* the delivery path. Only one copy is
now readable at runtime.

**A decline names a URL, not a URL within a Pack.** Turning down a suggestion
suppresses the standing offer for that URL whichever Pack later suggests it. That
matches how the rest of this works — `pending` matches a subscription by URL and
ignores which Pack it came from, because a Source is the reader's rather than the
Pack's — and it reads the decline as "I do not want this to be one of my
Sources", which is what the reader was actually asked. It is not free: a reader
who declines a URL under one Pack is never raised it under another, and the
built-in Packs are disjoint today only by chance. Installing that Pack by hand
still offers it, which is the escape hatch.

**An unchecked box counts as an answer wherever the box arrived checked.**
Accepting an offer records the suggestions left unticked as declined, because
the sheet arrives pre-ticked and unticking is therefore deliberate. Without this
the reader would untick three Sources, tap Add, and find those exact three
waiting in Settings. It does change the library flow, which previously forgot
the whole question on dismissal. Where an offer is long enough to arrive with
nothing ticked, the premise is absent and so is the conclusion: leaving a
suggestion unticked says nothing about it, and it stays in the standing offer.
See `PackSourceOffer.preCheckedUpTo`.

**Correction (2026-08-22):** this consequence read "**An unchecked box counts as
an answer, in both flows.** Accepting an offer records the suggestions left
unticked as declined, and the sheet arrives pre-ticked, so unticking is
deliberate." That was true of every offer the app could then make, because every
offer arrived pre-ticked. #20 capped what a Pack may suggest and stopped
pre-ticking offers past `PackSourceOffer.preCheckedUpTo`, which removed the
premise the rule rests on without narrowing the rule — so a reader who ticked
three of thirty-one silently declined the other twenty-eight, close to
permanently, on a list they were never shown as ticked. The decision stands; the
sentence was an absolute that stopped being true.

**Declines made before this shipped were not recorded, so they are asked once
more.** A reader who hand-installed a Pack on an earlier build and tapped "Not
now" left nothing behind for `standing` to consult, and that Pack's suggestions
surface in Settings on their first upgraded launch. One row, once, and it
self-corrects the moment they answer it. Migrating it is not possible — the
information was never written down — and "not now" was a fair description of what
that button meant at the time.

**A reader saying yes is necessary and is no longer sufficient.** Answering an
offer now asks each ticked suggestion whether it is really a feed, and does not
subscribe the ones that answer with something else (#58). That is a veto the app
did not have under this decision as written — "the reader is what subscribes"
narrows to "nothing is subscribed that the reader did not ask for". The veto is
deliberately narrow: only a host that *answered*, with something that is not a
feed, is refused. A refusal, a timeout or an empty answer says nothing about the
URL — reddit 429s a feed that is unquestionably a feed (ADR-0003) — so those are
subscribed, and if the trouble persists the Source says so on its own Settings
row (#14). What is turned away is **not** recorded as declined, because the
reader said yes: it stays in the standing offer, or one bad afternoon on the
host's side would bury it under the "close to permanent" rule above. The case
this exists for is a **generated** Pack (#27), whose suggested Sources are model
output and are trusted accordingly.

**`seedIfNeeded` installs the Pack before it touches Sources.** Which Sources a
reader should be offered comes from the Pack they are on, and which Pack that is
is only settled by `PackMigration.ensureBuiltinInstalled`. Anything added to
launch that acquires Sources has to run after it.
