# TechPulse — Privacy

TechPulse is built so that **your reading stays on your phone**. There is no
account and no server of ours. Everything the app sends off the device is listed
below in full, and that list is closed. **No passage of what you are reading is
on it**: the most any entry carries from an article is a single word you chose to
look up.

## What we collect

Nothing. There is **no account, no sign-in, no server of ours, and no analytics
SDK**. The App Store privacy label is "Data Not Collected".

## Where your data lives

Your Concepts, their Mastery, your reading history, Streak and quiz results live
in a local database inside the app's private sandbox. None of it is uploaded.

One small file sits outside that sandbox: so the home-screen and lock-screen
widgets can draw without running a database, the app writes a snapshot — the
Streak, today's count, the number of Lit Concepts and the Next Dot's name — into
an App Group container shared with the TechPulse widget. It stays on the device
and is readable only by this app and its own widget.

Your Reading Intention — the time you said you read, and the routine you said it
follows — is kept in the app's own preferences, and the reminder derived from it
is a **local** notification: scheduled on this device, delivered by this device.
No push service is involved, so nothing about when or whether you read is sent
anywhere. Turning the reminder off, or refusing the permission, changes nothing
else in the app.

## Network traffic

This section is the whole of it. Everything the app sends off the device has a
name in the project's own vocabulary — **Egress** — and the point of the name is
that this list is complete: a feature that adds a line here is changing what the
app promises, not adding a detail. Work done *on* the device, however much of
your reading it touches, is not on this list and never will be.

The app makes these outbound connections, all over HTTPS:

1. **Feed downloads** — the public RSS/Atom feeds of the Sources you enabled.
2. **Checking a suggested Source** — when you accept Sources a Pack suggested,
   the app fetches each one you ticked, once, to confirm it really is a feed
   before subscribing you to it. Same request as a feed download, to the same
   address, a moment earlier — and only for the ones you ticked. Nothing about
   you is sent, and one you left unticked is never contacted.
3. **Article pages** — when a feed carries only a snippet, the article's own page
   from its publisher, fetched when you open it. The same traffic as any news
   reader.
4. **arXiv search** — when you ask a Concept with little to read for more, the
   app queries `export.arxiv.org` for recent papers. **The Concept's name is
   sent** as the search term, so this one discloses what you are studying to
   arXiv. It happens only when you ask for it.
5. **Your own Claude key (optional)** — described next.

## The opt-in path: your own Claude key

If *you* add a Claude API key, two features use it, and they send different
things. Requests go **directly to api.anthropic.com under your key**, through no
server of ours (there is none).

- **Go deeper** — expanding a Concept sends that **Concept's name, definition and
  cluster**. No passage of any article — though a Concept's name may itself be a
  word the on-device analysis lifted from one you read.
- **Explain** — selecting a word in an article sends the **word you selected, the
  field your Pack covers, and the names of its Clusters**. No passage of the
  article. The model is told what you are studying, not what you are reading —
  "someone studying AI Engineering asked what LoRA means" — and that is what
  tells it which sense of an ambiguous term you meant. Nothing else from the
  article goes with it: not the sentence around the word, not the title, not the
  body. The word itself is article text, and it is the only article text there
  is. **A word already on your map sends nothing at all** — it opens the Concept
  you already have, offline, and the match allows for case, hyphens and plurals,
  so selecting "LoRAs" opens your "LoRA"
  ([ADR-0007](docs/adr/0007-explain-matches-the-map-on-spelling-not-on-meaning.md)).

On hardware with Apple Intelligence, Explain runs on-device and uses the sentence
around the word instead, which is a better clue and costs nothing because it
never leaves the phone. The two paths deliberately send different things; see
[ADR-0006](docs/adr/0006-explain-disambiguates-from-your-pack-not-from-the-article.md).

Both features work without a key on hardware with Apple Intelligence, where the
analysis runs on-device and nothing is transmitted. Remove the key any time in
Settings → AI engine, and both fall back to on-device or stop.

## Your API key

Your key is stored in the **iOS Keychain**
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — this device only, and
`kSecAttrSynchronizable` is left off, so we never sync it anywhere). It is never
written to logs, never sent anywhere except Anthropic's own API on your behalf,
and is removed from the Keychain when you delete it.

## Security posture

- **No third-party dependencies** — nothing in the app to compromise by way of
  someone else's package.
- Feed XML is parsed with external-entity resolution **disabled**.
- **Every response the app fetches** — a feed, an article page, a topic search,
  or a model reply on the opt-in path — is **discarded rather than parsed or
  stored** if it is over 5 MB. One limit, named once, so the sentence is true of
  the whole app rather than of the fetchers that happened to carry a copy of
  it. Note what this does and does not
  do: the response is already in memory by the time it is measured, so the limit
  bounds what the app keeps and works on, not what it allocates.
- An **imported Pack is untrusted input**: it is validated before anything is
  installed, and a Pack that fails is rejected with a reason rather than
  partially applied.
- Article text is treated as **attacker-controlled** — whoever writes a feed you
  subscribed to chooses those bytes. It is never auto-linked, and where any of it
  reaches a model — the word you selected on either Explain path, the surrounding
  sentence on the on-device one — it is passed as reference material under
  system-side instructions saying it is not to be followed as instructions.

## Imported Packs

A Pack is a file, and a file can come from anywhere. Installing one never
destroys what you have already learned: your Concepts, their Mastery and your
reading history survive a Pack change, and a Pack that would be ambiguous or
malformed is refused at import rather than allowed to corrupt your map.

---

*TechPulse does not generate Packs. If Pack generation ships, what leaves the
device on each of its paths will be described here before the feature is
released.*
