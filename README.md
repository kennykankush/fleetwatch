# Stockpile

Storage transparency for macOS — your disk, explained, not just displayed.

Every gig gets a name in plain words, a reason it exists, and a verdict on whether
it's safe to let go. No treemaps. No scare tactics. Honest numbers, both accountings.

Read [VISION.md](VISION.md) before building toward anything.

## Development

- macOS 26+, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- `xcodegen generate` → open `Stockpile.xcodeproj`
- Core logic lives in `Core/` (SPM package, headless, tested): `swift test` from `Core/`

## Architecture

| Piece | Home | Role |
|---|---|---|
| `RulesKit` | `Core/` | Versioned allowlist registry: what is safe to clear, and why |
| `ScannerKit` | `Core/` | Disk accounting (physical + effective) and directory scanning |
| `InventoryKit` | `Core/` | Installed-app census across sources (cask, formula, App Store, direct) |
| App | `App/` | SwiftUI shell — Overview, Descend, Apps, Startup, Ledger |

Safety model: 🟢 pure cache · 🟡 regenerable (with consequences) · 🔴 never suggested.
Nothing is ever `rm`'d — Trash only, every action recorded in the Ledger.
