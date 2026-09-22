<div align="center">
    <h1>📡 Fleetwatch</h1>
    <p><b>Every machine you own, and everything it's holding — in one window.</b></p>
</div>

![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-blue?style=flat-square)
![Swift](https://img.shields.io/badge/Swift-6-F05138?style=flat-square)
![License](https://img.shields.io/github/license/kennykankush/fleetwatch?style=flat-square)
![Status](https://img.shields.io/badge/status-pre--release-orange?style=flat-square)

Fleetwatch is a health and hardware monitor for a personal fleet. Open it and
you're in the cockpit: your Mac, your home server, your part-time Windows box,
and the cloud plans you pay for — added up into one honest number.

It watches and identifies. It never tortures hardware, never installs an agent
on a remote, and never writes to a machine that isn't the one in front of you.

> [!NOTE]
> Fleetwatch grew out of **Stockpile**, a one-Mac storage-transparency app. All
> of that is still here, under **Tools · This Mac** — it's just no longer the
> whole story.

## Fleet strength

The home screen answers one question: *what do I actually have?*

- **Total capacity** across every machine and cloud drive, with the split —
  how much is local, how much is cloud, how much is used.
- **Cores and memory** summed across the fleet, with how much is online now.
- **Owned, not merely reachable.** A machine that's asleep still counts. Its
  last known size is remembered and the tile says when it was last seen, so
  your total doesn't silently shrink when a box powers down.
- Machines never successfully read are shown as *unknown* rather than quietly
  counted as zero.

## Machines

- **Agentless.** Remotes are read over SSH with your existing keys and
  `~/.ssh/config` — over Tailscale if that's how you reach them. Nothing is
  installed on the far end, and no password is ever stored.
- **Linux, Windows and macOS** each get a native probe: one round trip gathers
  hardware identity, every fixed volume, memory, load, swap, Docker, GPU,
  temperatures, per-core load, and network/disk throughput.
- **Capability-detected organs.** A Linux box's dashboard looks like the Mac's,
  minus what it can't report. A Docker card only appears where Docker is.
  Missing organs simply don't show up.
- **Honest memory everywhere.** Cache is not "used" — on macOS, Linux *and*
  Windows, where the standby cache is separated out of the CIM numbers that
  would otherwise overstate free memory.
- **Uptime history and alerts.** Reachability is sampled and kept for a week.
  Notifications fire on the edges that matter — a machine dropping or
  returning, a vital crossing its threshold — not on every tick.

## Cloud

Cloud drives count toward your capacity, and they're **declared, not
discovered**. The sync clients mount through File Provider, so the OS reports
your local disk rather than the plan; no API will hand over a quota without
credentials. So you state what you own.

- **No sign-in, no token, no SDK.** A drive is a name and a number.
- **Optional live usage via [rclone](https://rclone.org).** If you already have
  remotes configured, point a drive at one and the provider answers for itself.
  `rclone` keeps the credentials — Fleetwatch never sees them, the same bargain
  it makes with your SSH agent.
- **The tile says where the number came from**: *Declared* or *Measured*. A
  typed figure never poses as a measurement.

## Tools · This Mac

Housekeeping stays where Trash and full disk access exist — local only. Remotes
are watch-only, permanently.

### Overview — the honest numbers
- [x] Physical **and** effective usage, side by side, always
- [x] Purgeable space measured and explained, not hidden
- [x] Disk snapshot recorded each launch (your storage gets a history)

### Descend — the inward granulizer
- [x] Click a folder and it becomes the canvas — descend, don't squint
- [x] Every recognized directory annotated in plain words with a safety tier:
      🟢 cache (regenerates itself) · 🟡 regenerable (costs a rebuild) · 🔴 your data (never suggested)
- [x] Session-cached sizing — revisits are instant, refresh on demand

### Apps — the totality, by source
- [x] Every app censused and classified: **App Store · Brew Cask · Brew CLI · Direct**
- [x] Sizes stream in live; last-used dates surface the forgotten
- [x] Homebrew read straight from disk (Caskroom/Cellar) — no subprocess, instant

### Startup — what actually runs at login
- [x] Login items, LaunchAgents, LaunchDaemons — each showing *what it runs*, in plain words
- [x] Live PIDs, keep-alive flags, disabled-state detection
- [x] Reversible controls for user-domain items (bootout + `.DISABLED` rename — never delete)
- [ ] Privileged helper for root-owned items

### Ledger — storage with a memory
- [x] Append-only record of every snapshot and every action
- [ ] Diffs between scans ("Spotify's cache regrew 2.1 GB this week")

## Widgets

- **Fleet strength** — total capacity, cores, memory and how many machines are
  reachable, including the sleeping ones.
- **Your disk, honestly** — physical and effective usage side by side, no
  purgeable games.

## The safety model

- **Remotes are read-only.** Telemetry in, nothing out. No remote deletion, no
  remote process control.
- **Credentials are never stored.** SSH auth is your agent's job; cloud auth is
  `rclone`'s. Fleetwatch stores a host, a user, and a number.
- **Local clearing is allowlist-only.** Fleetwatch can only suggest clearing
  paths a versioned rule explicitly recognizes — with guards like *`node_modules`
  only counts beside a `package.json`*. Anything unrecognized is your data and
  is untouchable, no matter how large.
- **Nothing is ever `rm`'d.** Trash only, every action recorded, everything
  reversible.

## Install

**Homebrew** (the repo is its own tap):

```sh
brew tap kennykankush/fleetwatch https://github.com/kennykankush/fleetwatch
brew trust kennykankush/fleetwatch   # newer Homebrew requires this for third-party taps
brew install --cask fleetwatch
```

**Installer script:**

```sh
curl -fsSL https://raw.githubusercontent.com/kennykankush/fleetwatch/main/scripts/install.sh | sh
```

**Manual:** grab `Fleetwatch-x.y.z.zip` from the
[latest release](https://github.com/kennykankush/fleetwatch/releases/latest),
unzip, drop into Applications. Signed with Developer ID and notarized by
Apple — it opens with no warnings.

**Optional, for live cloud usage:** `brew install rclone` and configure your
remotes. Without it, declared capacity still counts.

## Requirements

macOS 26 (Tahoe) or later. Native SwiftUI — no Electron, no runtime, no
background daemons. An anti-bloat app must not be bloat.

## Build from source

```sh
brew install xcodegen
git clone https://github.com/kennykankush/fleetwatch && cd fleetwatch
xcodegen generate && open Fleetwatch.xcodeproj
```

Core logic lives in `Core/` as a headless, tested Swift package
(`swift test` from `Core/` — 81 tests, under a second):

| Library | What it owns |
|---|---|
| `FleetKit` | machines, the SSH probes, cloud drives, fleet strength |
| `RulesKit` | the clearing allowlist |
| `ScannerKit` | dual accounting and honest sizing |
| `InventoryKit` | app census, startup catalog |
| `LedgerKit` | the memory |
| `ThermalKit` · `MemoryKit` · `BatteryKit` · `HonestKit` | the vitals |

## FAQ

**Why does Finder say I have way more free space than `df` does?**
Purgeable space. macOS promises it can auto-delete certain caches when space
runs low, and Finder counts that promise as free space. Fleetwatch shows both
numbers so you're never lied to. This exact confusion is the app's origin
story.

**Why is my cloud capacity something I have to type in?**
Because the alternative is asking you to sign in. Google Drive and OneDrive
mount through File Provider, so `statfs` reports your local disk, not the plan;
reading the real quota needs OAuth tokens Fleetwatch would then have to store.
Declaring it costs you one number and stores no secret. If you want it
measured, `rclone` already holds those tokens — point a drive at a remote.

**Does a machine have to be online to count?**
No. Capacity is remembered, so a part-time box keeps contributing its disks to
your total while it sleeps. The tile shows when it was last seen, and the
strength band says how many machines are being counted from memory rather than
live.

**Is it safe?**
Sizing never follows symlinks and never reads file contents (iCloud dataless
files stay in the cloud). Remotes are never written to. Local deleting is
Trash-only and ledger-recorded. The tier system is enforced in code and covered
by tests.

**Are the sizes exact?**
Allocated bytes on disk — honest for sparse files, and measured once then
cached until the mtime changes or you refresh. One blind spot we share with
every scanner including Finder: APFS clone files share storage under the hood
but each reports its full size, so sums can slightly exceed true usage. macOS
exposes no API to see clone sharing — anyone claiming clone-exact numbers is
guessing.

**Why no treemap?**
Treemaps show you bytes. Fleetwatch shows you *meaning*. If you want rectangles,
GrandPerspective is excellent.

## License

[MIT](LICENSE) — © 2026 Hadi Mulia
