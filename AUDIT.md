# AUDIT.md — structural ledger. Maintained by bedrock audits.

## Health board
| Subsystem | Grade | Last inspected |
|---|---|---|
| RulesKit matching (the allowlist) | sturdy — guards survived suite attack (impostor node_modules, venv child, prefix bleed); tier *semantics* have confirmed drift (F-004) | 2026-07-07 |
| ScannerKit SizeCache | sturdy — mtime validation, LRU, persistence attacked & held; path-alias hole confirmed (F-003) | 2026-07-07 |
| ScannerKit sizing/index | sturdy — symlink, dedup, canonicalization survived suite; not attacked under concurrency | 2026-07-07 |
| LedgerKit | **flaky** — corruption silently wipes history (F-002) | 2026-07-07 |
| InventoryKit uninstall path | **cracked** — leftover sweep over-collects by name (F-001); Trash-recoverability is the only net | 2026-07-07 |
| Clear/uninstall UI flows | not attacked — no UI harness; races suspected (F-005..F-008) | 2026-07-07 |
| StartupCatalog/Actions | not attacked this run | — |
| Widget/App Group bridge | not attacked this run | — |

## Open findings

F-001 [confirmed] [silent-wrong]
  Where:   Core/Sources/InventoryKit/UninstallAction.swift (LeftoverLocator.find)
  Claim:   finds "the standard places apps leave residue" for the app being uninstalled
  Reality: matches by NAME with zero ownership verification. Uninstalling any app whose
           name collides with a shared directory (e.g. an app named "Electron" vs
           ~/Library/Application Support/Electron used by every Electron dev project)
           sweeps other software's data into the Trash. APFS case-insensitivity widens
           the collision surface.
  Repro:   audit/repros/AuditProbeF001.swift (via run-repros.sh) — probe passes = flaw present
  Blast:   every uninstall; mitigated only by Trash recoverability + the confirm dialog
           listing leftover count (not paths).

F-002 [confirmed] [silent-wrong]
  Where:   Core/Sources/LedgerKit/Ledger.swift (LedgerStore.events/append)
  Claim:   "append-only… the app's memory"
  Reality: a corrupt/undecodable ledger file reads as empty with no error; the next
           append persists that empty view — entire history silently destroyed.
  Repro:   audit/repros/AuditProbeF002.swift — probe passes = flaw present
  Blast:   the Ledger feature, diff engine (latestSnapshot), lifetime stats ambitions.

F-003 [confirmed] [degrading]
  Where:   Core/Sources/ScannerKit/SizeCache.swift (raw-path keys)
  Claim:   invalidate(subtree:) forgets measurements under a path
  Reality: the same directory reached via a symlink alias has an independent cache key;
           invalidating one alias leaves the other entry stale. ReclaimableIndex stores
           resolved paths while Descend stores as-listed paths — two-key worlds exist.
  Repro:   audit/repros/AuditProbeF003.swift — probe passes = flaw present
  Blast:   stale sizes after clears on homes with symlinked dirs; low on stock setups.

F-004 [confirmed] [silent-wrong (product claim)]
  Where:   Core/Sources/RulesKit/Resources/rules.json (generic-xdg-cache, generic-library-cache,
           xdg-cache-root, library-caches-root)
  Claim:   tier "cache" = "regenerates itself — zero cost"
  Reality: ~/.cache contains full browser profiles with login sessions (observed:
           ~/.cache/hadi-tiktok-session/Default — cookies/logins). The generic tier
           offers one-click Trash of credentials under a "zero cost" label. The two
           ROOT rules additionally offer wholesale trash of the entire ~/Library/Caches
           / ~/.cache directory (including running apps' caches) presented identically
           to clearing one app's cache.
  Repro:   observational — `ls ~/.cache` (no deletion performed; blast radius rule)
  Blast:   the app's core trust promise. Trash-recoverable, but "zero cost" is false.

F-005 [suspected] [degrading]
  Where:   App/Sources/Descend/DescendView.swift (DescendModel.cache session dict)
  Reality: clearing an item in Caches invalidates SizeCache but NOT Descend's in-session
           dict — revisiting the parent folder shows the pre-clear size until Refresh.
  Settle:  manual — clear a node_modules in Caches, revisit its parent in Descend same session.

F-006 [suspected] [degrading]
  Where:   App/Sources/Caches/CachesView.swift (clear vs refresh/build race)
  Reality: clear() mutates items while build() may be in flight; a stale build snapshot
           (measured pre-trash) can resurrect the cleared row until next refresh.
  Settle:  UI harness or model-level interleaving test.

F-007 [suspected] [silent-wrong]
  Where:   Core/Sources/InventoryKit/AppCensus.swift (classify via caskToken name match)
  Reality: an installed cask token normalizing equal to an unrelated app's name
           misclassifies it as homebrewCask → uninstall runs `brew --zap` on the wrong
           token. Needs installed-cask + name collision to trigger.
  Settle:  make census roots injectable; fixture with colliding names.

F-008 [suspected] [degrading]
  Where:   CachesView.perform / AppsView.perform (owner-quit guard)
  Reality: 1s sleep after terminate() is a guess; slow-quitting apps still hold/rewrite
           cache mid-trash → partial regeneration, size ≠ 0 after clear.
  Settle:  poll NSRunningApplication.isTerminated with timeout instead of fixed sleep.

F-009 [suspected] [degrading (claim drift)]
  Where:   CachesModel.clear / VISION.md trust boundaries
  Reality: failed clears surface in a banner but are NOT ledgered; Startup failures are.
           "Every action recorded" ≠ behavior for the newest action type.
  Settle:  code reading is sufficient; one-line test after fix.

## Closed findings
(none yet — bootstrap run)

## Load-bearing map
- RulesKit.RulesRegistry.match — the vault door; every deletion suggestion flows through it
- ScannerKit: AllocatedSize (all sizing) · SizeCache (all caching, persisted App Support/Stockpile/sizecache.json) · ReclaimableIndex (Caches sector + Overview number) · TrashAction (THE deletion primitive)
- InventoryKit: AppCensus (classification → uninstall method choice) · LeftoverLocator/UninstallAction (multi-path deletion) · StartupCatalog/Actions (launchd mutations)
- LedgerKit.LedgerStore (App Support/Stockpile/ledger.json — memory, diffs)
- App: ReclaimableModel.shared (clear entry point) · WidgetBridge (App Group export)
- Ship path: scripts/release.sh → publish.sh → Casks/stockpile.rb (self-tap)

## Feature inventory
Overview (measure → snapshot → diff line) · Descend (browse/annotate, session cache, refresh) · Caches (index → clear-to-Trash w/ owner guard) · Apps (census → sizes → uninstall w/ leftover sweep) · Startup (catalog → reversible disable/remove) · Ledger (timeline) · Widget (App Group snapshot) · Release (publish.sh one-command)

## Run log
2026-07-07 · bootstrap, scope: deletion paths, allowlist, cache, ledger, census · suite 19/19 green · probes: 3 run, 3 confirmed flaws (F-001..003) + 1 observational (F-004) · suspected filed: 6 · not reached: UI flows (no harness), StartupCatalog/Actions, widget bridge, ReclaimableIndex under concurrency, publish pipeline
