# TechPulse — Privacy

TechPulse is built so that **your reading stays on your phone**. This is a
product principle, not a setting. There is one exception, it is opt-in, and it
is described in full below.

## What we collect

Nothing. There is **no account, no sign-in, no server of ours, and no analytics
SDK**. The App Store privacy label is "Data Not Collected".

## Where your data lives

Everything — the Pack you installed, which Concepts you have marked known, your
reading history, Streak, and quiz results — is stored in a local database inside
the app's private sandbox on your device. It is never uploaded.

## Network traffic

The app makes exactly these outbound connections, all over HTTPS:

1. **Feed downloads** — the public RSS/Atom feeds of the Sources you enabled,
   and, when a feed carries only a snippet, the article's own page from its
   publisher when you open it. The same traffic as any news reader.
2. **Your own Claude key (optional)** — if *you* add a Claude API key,
   "Go deeper" and word-level Explain send the relevant prompt **directly to
   api.anthropic.com using your key**. It passes through no server of ours
   (there is none). Remove the key any time in Settings → AI engine.

What is sent on the opt-in path is the **Concept** — its name, definition and
cluster. **Never article text**, and never your reading history, Mastery or
Streak. By default, with Apple Intelligence on-device or the built-in
`NaturalLanguage` fallback, even that analysis runs locally and nothing is
transmitted at all.

## Your API key

If you provide a Claude API key it is stored in the **iOS Keychain**
(`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` — this device only, and
`kSecAttrSynchronizable` is left off, so we never sync it anywhere). It is never
written to logs, never sent anywhere except Anthropic's own API on your behalf,
and is removed from the Keychain when you delete it.

## Security posture

- **No third-party dependencies** — nothing in the app to compromise by way of
  someone else's package.
- Feed XML is parsed with external-entity resolution **disabled**, and feed and
  article fetches are **size-capped** (5 MB) so a hostile or broken response
  cannot exhaust memory.
- An **imported Pack is untrusted input**: it is validated before anything is
  installed, and a Pack that fails is rejected with a reason rather than
  partially applied.
- Article text is treated as **attacker-controlled**: it is never auto-linked,
  and where it reaches a model it is passed as reference material under
  system-side instructions that say so, to limit prompt injection from a feed.

## Imported Packs

A Pack is a file, and a file can come from anywhere. Installing one never
destroys what you have already learned: your Concepts, Mastery and reading
history survive a Pack change, and a Pack that would be ambiguous or malformed
is refused at import rather than allowed to corrupt your map.

---

*TechPulse does not generate Packs. If Pack generation ships, the on-device and
BYO-key paths, and what a generated Pack is allowed to claim, will be described
here before the feature is released.*
