# TechPulse — Privacy

TechPulse is built so that **your reading stays on your phone**. There is no
account and no server of ours. What network traffic exists is listed below in
full, including one case where a fragment of article text does leave the device.

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

## Network traffic

The app makes these outbound connections, all over HTTPS:

1. **Feed downloads** — the public RSS/Atom feeds of the Sources you enabled.
2. **Article pages** — when a feed carries only a snippet, the article's own page
   from its publisher, fetched when you open it. The same traffic as any news
   reader.
3. **arXiv search** — when you ask a Concept with little to read for more, the
   app queries `export.arxiv.org` for recent papers. **The Concept's name is
   sent** as the search term, so this one discloses what you are studying to
   arXiv. It happens only when you ask for it.
4. **Your own Claude key (optional)** — described next.

## The opt-in path: your own Claude key

If *you* add a Claude API key, two features use it, and they send different
things. Requests go **directly to api.anthropic.com under your key**, through no
server of ours (there is none).

- **Go deeper** — expanding a Concept sends that **Concept's name, definition and
  cluster**. No article text.
- **Explain** — selecting a word in an article sends the **word you selected and
  roughly 220 characters of the surrounding article text**, so the model can tell
  which sense of an ambiguous term is meant. This is article text leaving the
  device, and it is the one case where that happens.

Both features work without a key on hardware with Apple Intelligence, where the
same analysis runs on-device and nothing is transmitted. Remove the key any time
in Settings → AI engine, and both fall back to on-device or stop.

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
- Feed and article responses over 5 MB are **discarded rather than parsed or
  stored**. Note what this does and does not do: the response is already in
  memory by the time it is measured, so the limit bounds what the app keeps and
  works on, not what it allocates.
- An **imported Pack is untrusted input**: it is validated before anything is
  installed, and a Pack that fails is rejected with a reason rather than
  partially applied.
- Article text is treated as **attacker-controlled** — whoever writes a feed you
  subscribed to chooses those bytes. It is never auto-linked, and where it
  reaches a model (the Explain path above) it is passed as reference material
  under system-side instructions saying it is not to be followed as
  instructions.

## Imported Packs

A Pack is a file, and a file can come from anywhere. Installing one never
destroys what you have already learned: your Concepts, their Mastery and your
reading history survive a Pack change, and a Pack that would be ambiguous or
malformed is refused at import rather than allowed to corrupt your map.

---

*TechPulse does not generate Packs. If Pack generation ships, what leaves the
device on each of its paths will be described here before the feature is
released.*
