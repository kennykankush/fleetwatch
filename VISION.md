# VISION.md — what this project is trying to be.

## The spark (verbatim, 2026-07-07)

Born mid-housekeeping-session, after Claude spent the morning killing stray launchd
agents, uninstalling Foxit/GitKraken/OpenClaw/Maxon, clearing 12GB of caches, and
solving the mystery of a disk meter that dropped from 66% to 37% overnight:

> "actually are you able to make me an app where — electron or rust idk — where im able
> to see whats app ive installed, brew etc etc, how many gigs, how many caches etc, dev
> cache state and a inward granulaizer for eample /dev has like 80gb of cache but i can
> click /dev and itl lshow /fantopy-hadi has this gig and beside has like a clear cache
> or smth, and then like a startup process. basically if u get what i mean, im just
> brainstorming but i want things of sotrage to be transparent if u get what i mean?"

> "i keep asking you (claude) to like devour my pc and tell me whats what and what i
> should clear but i want to basically just immortalise it as an app"

> "i want to see like transparency of my storage not in a persepctice or wiztree sake
> but more visually aesthetic"

> "no dna with burnrate please, burnrate was a fun project but i want to make sure this
> is production grade"

> "make sure frontend is super nice … like almost premium"

## The experience promise

Open Stockpile and your storage is **explained, not just displayed**. Every gig has a
name in plain words, a reason it exists, and a verdict on whether it's safe to let go.
The numbers never lie to you — it shows both truths (physical bytes on disk AND
effective space counting purgeable) because the day this app was conceived, a meter
that silently switched accounting methods caused a real "did I just lose 130GB?!"
scare. Stockpile exists so that never happens again.

The design anchor is **Apple's Health app, for storage**: a few beautiful honest
numbers, plain-language insight cards, and a descent into detail when you want it.
WizTree shows you bytes; Stockpile shows you *meaning*.

## Product shape

A macOS 26 SwiftUI app. **Full window + desktop widget. No menu bar presence.**

- **Overview** — the honest numbers (physical % and effective %, purgeable explained),
  insight cards ("Spotify's cache regrew 2.1GB this week"), reclaimable total.
- **Descend** — the "inward granulizer": click `~/dev` → it becomes the canvas, its
  children bloom inside (spring-animated zoom, `matchedGeometryEffect` energy). Every
  entry annotated: what it is, its tier, what clearing costs. **No treemap. Ever.**
- **Apps** — the totality of installed apps, categorized: **All · Homebrew Cask ·
  Homebrew CLI (formulae) · App Store · Direct installs**. Size, source badge,
  leftovers, last-used, and the *correct* uninstall path per source
  (`brew uninstall --zap` vs App Store delete vs manual sweep with leftover map).
- **Startup** — login items + LaunchAgents/Daemons, showing what each one actually
  runs, in plain words, with toggles. (Immortalizes the burnrate/akashalabs hunt.)
- **Ledger** — every scan is a snapshot, so you get diffs over time; every deletion is
  recorded (what, when, size, why the rule matched). The app has memory.
- **Widget** — the anti-Stats: honest disk numbers + "X GB reclaimable."

Deletion model: three tiers, loot-rarity flavored —
🟢 **pure cache** (regenerates, zero cost) · 🟡 **regenerable** (deletable, costs a
rebuild/re-download — always shown with consequences) · 🔴 **your data** (sacred, the
app will not even suggest it).

## First user

Hadi — a developer/producer whose disk fills with node_modules, Swift build dirs,
Python venvs, DAW media, game installs, and AI-tool caches, and who periodically asks
Claude to "devour my pc and tell me whats what." Stockpile is that session, resident.
Second user: anyone who has ever stared at a disk meter they didn't trust.

## The first serious workflow

The one that birthed it: open Stockpile → Overview shows the honest numbers → descend
into `~/dev` → `fantopy-hadi 19G`, with 7G flagged 🟡 as rebuildable artifacts → clear
them (to Trash, never rm) → Ledger records "July 7: freed 12.3GB" → widget updates.
Ten minutes of a Claude session, as thirty seconds of an app.

## Non-goals

- **Not a treemap.** Not GrandPerspective, not WizTree, not DaisyDisk-with-new-colors.
- **Not a "cleaner."** No scare tactics, no "247 issues found!", no auto-delete. It
  informs; the user decides.
- **No menu bar app.** Full window + widget only.
- **Not Electron, not Tauri.** Native Swift/SwiftUI — an anti-bloat app must not be
  bloat.
- **No Mac App Store build.** Sandboxing would neuter the scanner and launchd access.
  Developer ID + notarized, distributed directly.
- **No burnrate DNA.** Fresh codebase, production discipline from commit one.
- **AI is a cherry, never a crutch.** The deterministic rules registry is the product;
  an optional "ask Claude what this folder is" (off by default) may come later, but the
  core never depends on a network call.

## Taste & interface principles

- "quite aesthetic … super nice … almost premium" — the user's words are the bar.
  Liquid glass, depth, big confident numerals, macOS 26-native materials.
- Aesthetic is a *consequence of clarity*, not decoration on a grid.
- Plain words over identifiers: "Maxon's video editor," never `net.Maxon.Autograph`.
- Tier colors read like loot rarity — a gamer's inventory, not an admin console.
- The name is game-inventory language (Factorio/RimWorld stockpile zones); the app may
  wink at this ("your Mac is over-encumbered") but never cosplays as a game.

## Trust & safety boundaries

- **Allowlist-only suggestions**: the app may only propose deleting paths matched by a
  versioned rule. Unknown = untouchable, no matter how big.
- **Nothing is ever `rm`'d.** Trash only, always recoverable, every action in the
  Ledger.
- 🟡 deletions always show consequences before confirming. 🔴 is never suggested.
- If a cache's owning app is running (Spotify holding its cache), offer to quit it
  first — never yank files out from under a live process.
- Privileged (root-owned) operations arrive only with an explicit per-action prompt,
  via a proper helper — never silent sudo.

## Current direction (2026-07-07)

Scaffold: XcodeGen-managed project, `StockpileCore` as a headless tested SPM package
(scanner, rules, accounting), SwiftUI app shell. Swift 6 mode, macOS 26 minimum,
swift-testing. Build the Overview screen first — it sets the visual language. Seed the
rules registry from the live session that birthed the app (node_modules, .build,
target, .next, venvs, ~/Library/Caches, npm/uv/brew caches, Xcode Previews, simulator
data…).

## Open questions

- Startup manager: in v1, or v1.x? (Proposed v1.x; the user's own history argues v1.)
- Widget contents beyond honest % + reclaimable — what earns the space?
- "Descend" as the hero view's real name, or working title?
- The optional Claude-API "what is this folder?" — when, and what does it cost?
- Ship model when it ships: free, paid, license? (Personal tool first; shippable is
  the constraint, not the deadline.)
