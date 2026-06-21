# Zeus

**A native macOS terminal + project navigator.** Zeus autoscans every git project on your Mac and
presents them as a continuous, zoomable **constellation** — **Repo → Worktree → Branch → Commits** —
with an embedded full PTY terminal, fish-style right-arrow autocomplete, and a configurable animated
gradient background.

> Think *Warp + Fork + a tiling terminal*, native and GPU-smooth. Open Zeus and you instantly see
> every project on your machine; dive into a repo's worktrees, branches, and commit graph; and drop
> into a terminal that already knows the right working directory.

**Status:** active development · **Target:** macOS 26 (Tahoe), Apple Silicon · **Language:** Swift 6.2
(strict concurrency), SwiftUI + AppKit.

---

## The constellation UI

Zeus renders your projects as a star map and uses a continuous powers-of-ten **zoom** to move between
levels — each dive zooms *into* a focal star:

| Level | What you see |
|-------|--------------|
| **Hub** | Every repo as a star, clustered by type (frontend / backend / iOS / macOS / mobile / scripts). Fill color = git status (clean / dirty / ahead / behind / untracked). |
| **Worktrees** | The repo's worktrees as satellites orbiting the repo star, labeled by their checked-out branch. |
| **Branch tree** | The branch's commit history as a vertical constellation (newest on top), with a changed-files / diff panel. |

A full PTY terminal lives in the bottom panel on the Hub and Worktree levels; the branch tree swaps in
a Changes panel.

### Headline features

1. **Autoscan** — discovers all git repos under your dev roots, kept live via FSEvents.
2. **Repo → Worktree → Branch → Commits** — a navigable hierarchy built from real git data.
3. **Animated zoom UI** — spring transitions, ProMotion-friendly, honors Reduce Motion.
4. **Right-arrow autocomplete** — ghost-text suggestion in the input line; `→` accepts at end-of-line.
5. **Per-project workspace rail.**
6. **Full-fledged terminal** — real PTY, xterm-256color, your `$SHELL`, scrollback, resize, copy/paste.
7. **Configurable animated gradient background** — per-theme, live.

See [`SPEC.md`](SPEC.md) for the full product + technical spec.

---

## Tech stack

- **UI:** SwiftUI with AppKit bridges (`NSViewRepresentable`), `@MainActor @Observable` stores (UDF).
- **Terminal:** [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) over a local PTY.
- **Git:** reads via the `git` CLI (porcelain / `for-each-ref` / `git log`), shelled out with argv
  arrays (no shell injection). The `GitReading` port keeps libgit2 swappable.
- **Discovery:** `FileManager` deep enumeration (source of truth) + FSEvents for live updates.
  (Spotlight/`NSMetadataQuery` was evaluated and **deferred** — it never indexes `.git` dotfolders;
  see [`SPEC.md` §4.1](SPEC.md).)
- **Persistence:** [GRDB](https://github.com/groue/GRDB.swift)/SQLite for the scan index (instant cold
  start, incremental rescan); SwiftData for settings.
- **Distribution:** Developer ID + notarized, non-sandboxed (v1). Requests Full Disk Access so live
  refresh works on TCC-protected folders (Desktop / Documents / Downloads).

---

## Architecture

Zeus follows a clean **ports-and-adapters** layering with a strict inward dependency rule, shipped as a
local Swift package (`Packages/ZeusKit`) consumed by the Xcode app target.

```
ZeusDomain      pure entities, use cases, and port protocols — NO framework imports, 100% unit-tested
   ▲
   │  (adapters implement the domain's ports)
ZeusGit         GitReading        — git CLI shell-out
ZeusScanner     ProjectScanning   — FS enumeration, FSEvents watcher, Full Disk Access probe
ZeusIndex       RepositoryIndexStore — GRDB/SQLite scan index
ZeusSettingsStore  SettingsStoring — SwiftData
ZeusTerminal    SwiftTerm PTY view
ZeusSuggest     SuggestionProviding
   ▲
ZeusUI          SwiftUI views + @Observable feature stores (HubDataStore, WorktreeOrbitStore,
                CommitTreeStore, NavigationStore) — pure reducers drive navigation/zoom
   ▲
Zeus (app)      composition root — wires concrete adapters into the UI stores
```

Off-main work (scan, git, suggest) runs off the `@MainActor`; only published state resumes on main.

### Project layout

```
Zeus/
├── SPEC.md                       # full product + technical spec, research spikes
├── CLAUDE.md                     # contributor workflow (TDD, skills, guardrails)
├── Design/                       # design handoff + HTML prototypes
├── Packages/ZeusKit/             # the Swift package (all logic + tests)
│   ├── Sources/{ZeusDomain,ZeusGit,ZeusScanner,ZeusIndex,
│   │            ZeusSettingsStore,ZeusTerminal,ZeusSuggest,ZeusUI}
│   └── Tests/                    # Swift Testing / XCTest unit + fixture tests
└── Zeus/                         # the Xcode app target (Zeus.xcodeproj)
```

---

## Build · Run · Test

**Requirements:** macOS 26 (Tahoe) · Apple Silicon · Xcode 26 · Swift 6.2.

### Package (fast inner loop)

All domain + adapter logic lives in `ZeusKit` and is tested with plain SPM:

```bash
cd Packages/ZeusKit
swift test          # 200+ unit / fixture tests
swift build
```

### App

```bash
# from the repo root
xcodebuild -project Zeus/Zeus.xcodeproj -scheme Zeus -configuration Debug build
```

Then run from Xcode (⌘R) or launch the built `Zeus.app`.

> **First-build gotcha:** the app target compiles SwiftTerm's Metal shaders, which needs the Metal
> Toolchain component. If the build fails on `Shaders.metal`, install it once:
> `xcodebuild -downloadComponent MetalToolchain`. (Plain `swift build` doesn't need it.)

On first run, grant **Full Disk Access** (System Settings → Privacy & Security → Full Disk Access) so
the live scan + FSEvents refresh reach your project folders. Zeus shows a dismissible banner if it
detects this is needed.

---

## Status

| Area | State |
|------|-------|
| Embedded PTY terminal (SwiftTerm) | ✅ real shell, truecolor, resize |
| Git reads (worktrees, branches, commits, diff, status) | ✅ via `git` CLI, fixture-tested |
| Constellation zoom UI (hub / worktrees / branch tree) | ✅ |
| Autoscan + classify + GRDB index (instant cold start) | ✅ two-phase cached → live paint |
| Configurable scan roots (Settings) | ✅ |
| Live refresh (FSEvents) + Full Disk Access hint | ✅ |
| **Hub** level fed by real git | ✅ |
| **Worktree** (orbit) level fed by real git | ✅ |
| **Branch tree** fed by real git | ✅ single-branch history (newest commits) |
| Changes-panel real diff | 🚧 next (currently a placeholder for real shas) |
| Multi-branch commit graph, scroll pagination | 🚧 planned refinements |
| Right-arrow autocomplete, gradient editor, per-project tabs | 🚧 planned |

Spotlight discovery accelerator was evaluated and **deferred to v2** (negative spike result, see
`SPEC.md` §4.1). Distribution (Developer ID + notarization) is set up for non-sandboxed v1.

---

## Contributing

Development is **test-first (TDD is mandatory)** — Red → Green → Refactor on every feature, tests
committed alongside the code. The full workflow, architectural rules, and definition of done live in
[`CLAUDE.md`](CLAUDE.md); the product/technical spec and research spikes live in [`SPEC.md`](SPEC.md).
Start there before adding features.
