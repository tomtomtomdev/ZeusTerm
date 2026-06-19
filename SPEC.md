# Zeus — Research Plan & Build Spec

> A native macOS terminal + project navigator that autoscans every coding project on your
> Mac, organizes them as **Repo → Worktree → Branch → Commits**, and presents them in a
> beautifully animated, gradient-themed interface with a full-fledged embedded terminal and
> fish-style right-arrow autocomplete.

**Status:** Greenfield spec. **Target:** macOS 26 (Tahoe), Apple Silicon. **Lang:** Swift 6.2 / SwiftUI + AppKit bridges.

---

## 1. Product Vision

Zeus is "the launcher you live in." Open it and instantly see every git project on your
machine, drill into worktrees/branches/commits, and drop into a terminal that already knows
the right working directory. It feels closer to **Warp + Fork + a tiling terminal**, native
and GPU-smooth, with a configurable animated gradient identity.

### The 7 headline features

| # | Feature | One-line definition |
|---|---------|---------------------|
| 1 | **Autoscan** | Discover all git projects on disk, keep the index live. |
| 2 | **Repo → Worktree → Branch → Commits hierarchy** | A 4-level navigable tree built from real git data. |
| 3 | **Beautiful animated UI** | Spring transitions, matched-geometry tab moves, 120 Hz ProMotion-friendly. |
| 4 | **Right-arrow autocomplete** | Ghost-text suggestion in the input line; `→` accepts (fish/zsh-autosuggestions model). |
| 5 | **Side tabs per project** | Vertical project rail; each project is a workspace holding sessions + repo tree. |
| 6 | **Full-fledged terminal** | Real PTY, VT100/xterm-256color, your `$SHELL`, scrollback, resize, copy/paste, links. |
| 7 | **Configurable gradient background** | Linear/radial/angular/mesh, animated, per-theme, live preview. |

---

## 2. Feature Breakdown (detailed)

### 2.1 Autoscan
- **Discovery sources (in priority order):**
  1. **Manual deep enumeration** of dev roots (`~/Developer`, `~/Projects`, `~/Code`, `~/src`,
     `~/work`, `~/git`, `~/Documents`, plus user-added roots). `FileManager.enumerator` with
     `.skipsHiddenFiles = false`, pruning heavy dirs (`node_modules`, `.build`, `DerivedData`,
     `Pods`, `vendor`, `target`, `.venv`).
  2. **Spotlight (`NSMetadataQuery`)** as an accelerator — query for items named `.git`.
     ⚠️ **Research spike required** (see §4): Spotlight historically does not index dotfolder
     contents, so treat this as best-effort, not the source of truth.
  3. **Live updates** via **FSEvents** (`FSEventStreamCreate`) watching the dev roots so the
     tree updates as repos appear/disappear/commit.
- A repo = a directory containing `.git` (dir) **or** a `.git` file (worktree/submodule pointer).
- Index is cached so cold start is instant; rescan is incremental.

### 2.2 Repo → Worktree → Branch → Commits
This hierarchy is the **data model**; it is *presented* as the **constellation** (§7) — repos as
clustered stars, worktrees as orbiting satellites, branches/commits as a vertical commit graph.
- **Repo**: canonical git dir (the "common dir").
- **Worktree**: from `git worktree list --porcelain` (libgit2 worktree bindings are thin —
  shell-out is the reliable path). Main checkout + linked worktrees.
- **Branch**: local + remote-tracking refs; mark current HEAD, ahead/behind counts.
- **Commits**: revwalk (libgit2) of the selected branch — sha, summary, author, date, graph lane.
- Lazy-load commits (page on scroll); never walk full history eagerly.

### 2.3 Beautiful animated UI
- SwiftUI `withAnimation(.spring)`, `matchedGeometryEffect` for tab/panel moves, `.transition`
  for tree expand/collapse, `PhaseAnimator`/`KeyframeAnimator` for accents.
- Respect **Reduce Motion**; cap work to stay at display refresh (60/120 Hz).

### 2.4 Right-arrow autocomplete
- **Headline approach — app-managed suggestion line:** a custom input editor renders the typed
  command plus dimmed **ghost text** of the best suggestion; pressing `→` (when caret at end)
  accepts it, then the line is written to the PTY.
- **Suggestion ranking:** shell history (frecency) + filesystem path completion + git subcommand
  knowledge + recent commands in this project. Async, debounced, cancelable (actor-backed).
- **Fallback / complement:** ship a `zsh-autosuggestions`/`fish` integration so even raw PTY
  input gets native right-arrow accept when the custom line isn't in use.

### 2.5 Side tabs per project
- Left **project rail** (vertical, icon + name, reorderable, pinnable). Selecting a project opens
  its **workspace**: repo tree + one-or-more terminal sessions (their own inner tab strip).
- Per-project state persists (open sessions, cwd, scroll).

### 2.6 Full-fledged terminal
- **SwiftTerm** `LocalProcessTerminalView` embedded via `NSViewRepresentable`.
- Spawn `$SHELL -l`, inherit/clean env, set cwd to selected worktree path, `TERM=xterm-256color`.
- Scrollback, selection, copy/paste, clickable URLs, resize→`SIGWINCH`, mouse reporting, 256/true-color.
- Multiple concurrent sessions; each is an independent PTY.
- **Future GPU path:** `libghostty` (Metal) behind the same protocol — see §5.

### 2.7 Configurable gradient background
- Types: **linear / radial / angular / mesh** (`MeshGradient`, macOS 15+).
- Editable color stops, angle, animation speed, opacity, background blur/material, per-theme.
- Live preview in Settings; presets ("Aurora", "Sunset", "Mono", "Matrix"); import/export JSON.
- Rendered behind terminal text with adjustable text contrast safeguard.

---

## 3. Technical Architecture

Clean-ish layering with Unidirectional Data Flow in the presentation layer (see
`swiftui-architecture` + `clean-architecture` skills). Dependencies point inward.

```
┌──────────────────────────────────────────────────────────────┐
│ Presentation (SwiftUI + AppKit bridges)                        │
│  Views • @Observable Stores (UDF) • NSViewRepresentable bridges│
├──────────────────────────────────────────────────────────────┤
│ Domain (pure Swift, no framework imports)                      │
│  Entities: Project, Repository, Worktree, Branch, Commit       │
│  UseCases: ScanProjects, BuildRepoTree, OpenSession,           │
│            Suggest, UpdateTheme                                 │
│  Protocols (ports): GitReading, ProjectScanning, Terminal,     │
│            SuggestionProviding, SettingsStoring                 │
├──────────────────────────────────────────────────────────────┤
│ Data / Infrastructure (adapters)                               │
│  GitService (libgit2 + git CLI) • ProjectScanner (FS+Spotlight │
│  +FSEvents) • TerminalService (SwiftTerm PTY) • SuggestionEngine│
│  • SettingsStore (SwiftData) • IndexCache (GRDB/SQLite)        │
└──────────────────────────────────────────────────────────────┘
```

### Module map (Swift packages / targets)
- `ZeusDomain` — entities + use case protocols (no deps, 100% unit-testable).
- `ZeusGit` — libgit2/SwiftGitX wrapper + `git worktree` shell-out adapter.
- `ZeusScanner` — FS enumeration, Spotlight, FSEvents; actor-isolated.
- `ZeusTerminal` — SwiftTerm bridge + PTY/session management.
- `ZeusSuggest` — frecency history + path + git-subcommand suggestion engine.
- `ZeusUI` — SwiftUI views, stores, theming, gradient engine, animations.
- `Zeus` (app target) — composition root / DI wiring.

### Concurrency
- Swift 6 strict concurrency. Scanner, git reads, and suggestions run off-main on **actors**;
  UI stores are `@MainActor @Observable`. PTY callbacks marshaled to main.

---

## 4. Research Plan (spikes to de-risk before committing)

Each spike is a tiny throwaway prototype with a pass/fail acceptance test. Run them **first**.

| # | Spike | Question | Acceptance criteria |
|---|-------|----------|---------------------|
| S1 | Terminal embed | Does SwiftTerm give us a real, resizable PTY in SwiftUI with copy/paste + 256color? | Run `vim`, `htop`, `claude`; resize reflows; truecolor renders. |
| S2 | Right-arrow accept | Can we render ghost text + accept on `→` and inject to PTY cleanly? | Type partial cmd, `→` completes, `Enter` runs it. |
| S3 | Worktree truth | libgit2 worktree API vs `git worktree list --porcelain` — which is reliable? | All linked worktrees + branches enumerated for a multi-worktree repo. |
| S4 | Spotlight for `.git` | Does `NSMetadataQuery` surface `.git` dirs, or must we enumerate manually? | Decide primary discovery strategy; document indexing limits. |
| S5 | Scan performance | Time to index a disk with ~500 repos / deep `node_modules`? | < 3 s warm, pruning works, FSEvents keeps live. |
| S6 | Gradient perf | Animated `MeshGradient` behind a busy terminal at 120 Hz — CPU/GPU cost? | Stable frame time, no terminal jank; falls back gracefully. |
| S7 | libghostty | Is GPU terminal embedding feasible/worth it now (unstable C API)? | Go/No-go for v2; SwiftTerm stays v1 default. |
| S8 | Sandbox vs FDA | App Store sandbox + security-scoped bookmarks, or Developer ID + Full Disk Access? | Choose distribution; confirm scanning works under it. |

**Default decisions if a spike is inconclusive:** SwiftTerm (not libghostty) for v1; manual FS
enumeration (Spotlight only as accelerator); `git` CLI shell-out for worktrees; Developer ID +
non-sandboxed for v1.

### Spike outcomes
| # | Date | Verdict | Notes |
|---|------|---------|-------|
| S1 | 2026-06-19 | ✅ **GO — SwiftTerm** | `LocalProcessTerminalView` (SwiftTerm 1.13.0) wrapped in a SwiftUI `NSViewRepresentable` (`ZeusTerminal.TerminalEmulatorView`) gives a real PTY: harness spawns a `-zsh` login shell on `/dev/ttys005` as foreground session leader. Truecolor + 256-color render and `htop`/`vim` reflow on resize (verified in the `S1TerminalSpike` run harness). Shell launch params (`TERM=xterm-256color`, `COLORTERM=truecolor`, login argv0) are pure + unit-tested in `TerminalLaunchConfig`. Host app must stay **non-sandboxed** (§8). |

---

## 5. Tech Stack & Dependencies

| Concern | Choice | Notes |
|---------|--------|-------|
| Language / UI | Swift 6.2, SwiftUI (+ AppKit bridges) | Target macOS 26; `MeshGradient` needs 15+. |
| Terminal | **SwiftTerm** (`migueldeicaza/SwiftTerm`) | Pure-Swift, stable API, AppKit view. `libghostty` = future GPU path. |
| Git reads | **SwiftGitX** or **SwiftGit2/SwiftGit3** (libgit2) | Branches, commits, status. |
| Worktrees | **`git` CLI shell-out** (`worktree list --porcelain`) | libgit2 worktree bindings are thin. |
| Discovery | FileManager + NSMetadataQuery + FSEvents | See S4/S5. |
| Persistence | **SwiftData** (settings/themes) + **GRDB/SQLite** (scan index) | Index needs speed at scale. |
| DI / composition | Manual constructor injection | Keep it simple; no heavy DI framework. |
| Project gen | Xcode project or **Tuist** | Tuist if multi-package gets noisy. |
| Distribution | Developer ID + notarization (v1) | Sandbox + App Store as a later variant. |

---

## 6. Data Model (domain entities)

```swift
struct Project: Identifiable { let id: UUID; var name: String; var rootURL: URL; var repo: Repository }
struct Repository: Identifiable { let id: UUID; var commonDir: URL; var worktrees: [Worktree]; var remotes: [Remote] }
struct Worktree: Identifiable { let id: UUID; var path: URL; var isMain: Bool; var head: Branch?; var isLocked: Bool }
struct Branch: Identifiable { let id: UUID; var name: String; var isCurrent: Bool; var upstream: String?; var ahead: Int; var behind: Int }
struct Commit: Identifiable { let id: String /*sha*/; var summary: String; var author: Signature; var date: Date; var parents: [String] }

// For the branch-tree Changes panel (View 3). `parents` above feeds the graph edges/lanes.
enum FileStatus { case added, modified, deleted }
struct FileChange: Identifiable { let id: String /*path*/; var path: String; var status: FileStatus; var additions: Int; var deletions: Int }
struct CommitDiff { let sha: String; var files: [FileChange]; var patch: String /*unified diff for preview*/ }
```
Persisted **IndexEntry** (GRDB) holds `rootURL`, `lastScanned`, `headSHA` for fast incremental rescans.

> **Note (vs. P2 as built):** the implemented `Commit` carries `authorName`/`date` but **not yet
> `parents`** — the constellation branch-tree needs parent links to draw lane edges, so P2's commit
> read gains a `parents`/graph field (small TDD extension) alongside the new `CommitDiff` read.

---

## 7. UI / UX Spec — the Constellation model

> **Canonical design:** `Design/HANDOFF.md` (full token tables, copy, fidelity notes) and the
> interactive prototypes `Design/ZeusTerm-Live.dc.html` (state + geometry source of truth) and
> `Design/ZeusTerm-static-frames.dc.html` (light-theme reference). The HTML is a *design
> reference*, **not** code to port — translate the geometry/state algorithms, don't transpile the
> bespoke `<x-dc>` runtime. This section is the canonical product spec; the design files hold the
> exact seed coordinates/data.

Zeus presents the **Repo → Worktree → Branch → Commits** hierarchy as a **constellation** explored
through one continuous, nested "powers-of-ten" **zoom**. A child level lives *inside* the node you
click and is anchored at that node's position, so diving in and backing out are exact reverses and
the user keeps a persistent sense of *where they are*.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Topbar 54px:  ⚡ ZeusTerm  │  ZeusTerm / {project} / {branch}   [detached] ☀︎☾ │
├──────────┬─────────────────────────────────────────────────────────────────┤
│ Rail     │  Canvas — centered 1040×540 "stage" (zoom transforms apply here)  │
│ 236px    │     ✦   ✦      one of three levels, see below                     │
│ title/   │   ✦  ★(hub) ✦      (frosted ‹ Back pill, top-left, below hub)     │
│ legend/  │        ✦   ✦                                                       │
│ hint     │                                                                    │
├──────────┴─────────────────────────────────────────────────────────────────┤
│ Bottom panel:  terminal (hub/worktree)  OR  Changes+diff (branch tree)       │
└──────────────────────────────────────────────────────────────────────────┘
```

**Layout:** single window (radius 14px). **Topbar 54px** · **Body { left rail 236px | canvas
(flex) }** · **bottom panel** (terminal 196px / Changes 232px). The canvas hosts a **1040×540
stage** centered both axes; all node coordinates are in stage space; the stage is the unit zoom
transforms apply to.

### Three zoom levels
1. **Hub — "All projects."** Every detected repo is a *star*, clustered by project **type**
   (Frontend/Backend/iOS/macOS/Mobile/Scripts), **fill = git status**, faint constellation lines
   join cluster members and tie each cluster to a central monorepo hub star (gold, 16px). Star size
   6–11px; 34×34 invisible hit target; nebula radial-gradient background + ~56 twinkling bg stars.
   Click a non-hub star → dive into its **Worktrees**.
2. **Worktrees — orbit.** The repo star sits centered (17px gold, white border, big glow); its
   linked worktrees are *satellites* on **3 dashed elliptical orbit rings** (ry = rx×0.72; radii
   115/180/242 holding 3/4/3 nodes; per-ring angle offsets 0.4/0.85/0.15), each a 9.5px
   status-colored star with a radially-placed branch label. Click a satellite → dive into its
   **Branch tree** (resets HEAD/selection to the tip).
3. **Branch tree — commit constellation.** Time flows **top→bottom (newest→oldest)**. Branches are
   vertical **lanes** (columns) with name pills near each lane's newest commit; commits are
   branch/status-colored nodes joined by 2px branch-colored edges; a faint left axis (LATEST ▼
   OLDEST). The **HEAD** node is 15px with a white ring; a **selected** non-HEAD node gets a white
   selection ring; commits **newer than HEAD** are dimmed (`opacity .3; grayscale .5`). Hash printed
   under each node.

### Bottom panel
- **Hub / Worktrees → terminal** (the embedded PTY, feature #6). Tab shows cwd; sample prompt lines
  echo the `zeus scan` / `zeus open` / `git worktree list` actions.
- **Branch tree → Changes panel (232px)**, replacing the terminal: header (status dot + hash +
  message + `author · time`, plus a **● HEAD** badge or a **Checkout** button); body split = left
  46% "CHANGED FILES · n" rows (status letter M/A/D + path + `+adds`/`-dels` + add/del bar), right =
  a diff preview (file header, gray `@@` hunk, context / red `-` / green `+` lines).

### Interactions
- **Hub star click** → `dive(work)`; **worktree click** → `dive(tree)`.
- **Commit single-click** → select (Changes panel updates). **Double-click** (or the header
  **Checkout** button) → checkout: HEAD ring moves, newer commits dim, topbar shows
  `detached HEAD @{hash}`.
- **Back:** a frosted **‹ Back** pill floats top-left of the canvas (below hub only); the topbar
  **breadcrumb** does the same and supports multi-level hops.

### Zoom motion (the core animation)
One stage, transformed in phases on the **focal node** (`transform-origin` = clicked node's stage
x,y). `BIG = zoomDepth` (default **7**); `SMALL = (1/BIG)×1.15` (≈0.16) — reciprocals, so the
scale step between levels reads as constant.
- **leave (~460ms):** pivot on focal node, fade out. Dive-in scales `1→BIG`; back scales `1→SMALL`.
  Easing `cubic-bezier(.6,0,.78,0)`.
- **enter (instant set):** incoming level mounts pre-scaled at the same focal node (dive-in starts
  `SMALL`; back starts `BIG`).
- **idle (~520ms):** settle to `scale(1)`, opacity 1; easing `cubic-bezier(.16,1,.3,1)`.
- An **origins stack** pushes the focal node per dive and pops on back, so reverse zoom pivots on
  the right boundary node. Phase switches at 430ms → enter, 480ms → idle. **Pointer events disabled
  while `phase != idle`.** **Reduce Motion:** drop transitions, switch instantly.

### Layout algorithms (reproduce or replace; keep the visual character)
- **Hub clusters:** members on a jittered ring around each cluster center — `angle = i/n·2π +
  jitter + clusterPhase`, `radius = spread·(0.42…1.02)`, `y ×0.82` (flatter); seeded PRNG
  (mulberry32, seed 1337) for stability. Background stars use seed 99.
- **Worktree orbits:** elliptical, `ry = rx·0.72`, nodes evenly spaced per ring + per-ring offset.
- **Branch tree:** hand-placed lane columns + time rows (see `cdef` in the Live file). Newest on top.

> In production these are fed by real data (FS scan for repos, `git worktree list`, `git log` graph,
> `git show`/diff for the Changes panel). You may swap the seeded layout for a deterministic
> graph-layout engine, but preserve the look (clustered glowing stars, lines, orbits, vertical graph).

### Design tokens (summary — full tables in `Design/HANDOFF.md`)
- **Git status (the only semantic color scale; drives node fill):** clean `#35D08B`, dirty
  `#F5A623`, ahead `#6E8BFF`, behind `#FF6B6B`, untracked `#8B93A7`. Project **types** are *not*
  color-coded (spatial clustering + neutral outlined markers instead).
- **Branch lanes:** main `#F5C451` (Zeus gold), develop `#6E8BFF`, feature/* `#B98BFF`, fix/* `#57E0FF`.
- **Dark theme:** app `#0A0B10`, rail `#0C0E13`, panel `#080A0E`, control `#14171F`, accent-soft
  `#2A3350`; text hi `#E7EAF2` / mid `#9AA3B8` / dim `#646C80`. **Light theme** from static frame ③.
- **Type:** Geist (UI) + Geist Mono (terminal/hashes/pills/paths/diff) — or SF Pro / SF Mono for a
  native feel. Icons → SF Symbols (`bolt.fill`, `magnifyingglass`, `arrow.triangle.branch`,
  `sun.max`, `moon.fill`). **Star glow:** `0 0 {size*2} {size*0.6} {color}66, 0 0 4 1 {color}`.
- Radii: window 14 / cards 10–11 / controls 7–8 / pills 6–7. Both **dark + light** themes ship; the
  moon/sun topbar toggle switches them.

### Accessibility
- **Reduce Motion** removes zoom transitions (instant level switches). **Increase Contrast** boosts
  text/node contrast. Full **keyboard navigation** of stars/orbits/commits (the star map is not
  mouse-only) and **VoiceOver** labels on every node (name · type · git status / branch · hash ·
  message). The constellation is a visualization *over* a navigable model — the model stays operable
  without the visuals.

---

## 8. Distribution & Permissions
- **v1: Developer ID + notarized, non-sandboxed.** Scanning the whole disk is the core feature;
  prompt for **Full Disk Access** (or scope to user-chosen roots) on first run.
- **v2 option: App Store sandbox** using **security-scoped bookmarks** for user-granted folders.
- Hardened Runtime; sign embedded `git`/helper if bundled; staple notarization ticket.

---

## 9. Build Roadmap (milestones)

| Phase | Deliverable | Primary skills |
|-------|-------------|----------------|
| **P0 Setup** | Repo, `CLAUDE.md`, SPM packages, app shell + window, deps wired | `macos-development`, `/init` |
| **P1 Spikes** | Run S1–S8, record decisions | `macos-development`, `deep-research` |
| **P2 Domain + Git** | Entities, use cases, `ZeusGit` (CLI shell-out), unit tests. **✅ done** (`96fc3e0`). Follow-on: commit `parents` + `CommitDiff` read (`git show`/diff) for §7 View 3 | `clean-architecture`, `tdd-kent-beck` |
| **P3 Scanner** | `ZeusScanner` (FS+Spotlight+FSEvents), GRDB index, incremental rescan → feeds Hub stars | `macos-development`, `xunit-test-patterns` |
| **P4 Constellation UI** | §7 model: pure `ConstellationLayout` (hub clusters / orbits / commit lanes), `NavigationStore` UDF zoom state machine (view/phase/dir/origins, dive/back), SwiftUI stage + Hub/Worktree-orbit/Branch-tree views + rail + topbar/breadcrumb + Changes panel | `swiftui-architecture`, `clean-architecture` |
| **P5 Terminal** | SwiftTerm bridge in the bottom panel (hub/worktree views), sessions | `macos-development` |
| **P6 Autocomplete** | Suggestion engine + ghost text + `→` accept | `swiftui-architecture`, `clean-code` |
| **P7 Theme/Gradient** | Design tokens + dark/light themes + sun/moon toggle, nebula gradients, glow; Settings live preview/presets | `swiftui-architecture` |
| **P8 Polish/Ship** | Zoom-motion polish + Reduce Motion, a11y/keyboard/VoiceOver on the star map, perf (120Hz canvas), notarize/package, `/code-review` + `/security-review` | `refactoring-fowler`, `/security-review` |

---

## 10. Claude Code Workflow — Skills & Agents

### Skills to invoke (from this environment)
**Core build:**
- **`macos-development`** — primary; every Swift/SwiftUI/AppKit/Xcode/packaging task.
- **`swiftui-architecture`** — UI state, `@Observable` stores, UDF, navigation, modularization.
- **`clean-architecture`** — layer boundaries, ports/adapters, keeping domain framework-free.

**Quality:**
- **`clean-code`** — naming, function/class hygiene during implementation.
- **`refactoring-fowler`** — smell-driven cleanups (P8 and as you go).
- **`tdd-kent-beck`** — test-first for domain + use cases.
- **`xunit-test-patterns`** — Swift test-double/fixture design for git & scanner adapters.
- **`xcui-automation-testing`** — end-to-end UI flows (open project → tree → terminal).
- **`urlsession`** — only if/when remote git status or update-checks are added (minimal in v1).

**User-invocable slash commands:**
- **`/init`** — generate the project `CLAUDE.md` (then refine with §11 / the file written here).
- **`/run`** — launch the app to see changes live.
- **`/verify`** — confirm a feature actually works in the running app.
- **`/code-review`** — review diffs before merge.
- **`/security-review`** — audit the scanning + Full Disk Access + shell-out surface.
- **`/simplify`** — reuse/efficiency cleanups after a feature lands.
- **`/fewer-permission-prompts`** — reduce permission friction for the many `git`/`swift build` calls.
- **`deep-research`** — for the S7 (libghostty) / S4 (Spotlight) open questions.

### Agents to delegate to
- **`Plan`** — per-phase implementation plans before coding.
- **`Explore`** — read SwiftTerm/SwiftGitX APIs and example code.
- **`general-purpose`** — multi-step spikes (e.g., wire S1 prototype end-to-end).
- **`macos-development`** skill pairs with these agents for Swift specifics.
- *(figma-\* and ios-testing agents are iOS-oriented — lower relevance here.)*

---

## 11. Testing Strategy
- **Domain/use cases:** pure unit tests, TDD (`tdd-kent-beck`).
- **Git adapter:** integration tests against fixture repos created in `setUp` (`git init`, add
  worktrees) — characterize real output (`xunit-test-patterns`).
- **Scanner:** temp-dir fixtures with nested repos + ignored heavy dirs; assert pruning + counts.
- **UI:** XCUITest happy paths (`xcui-automation-testing`); snapshot the gradient/themes.
- **Manual:** `/verify` + `/run` for terminal interactivity (vim/htop), right-arrow accept.

---

## 12. Risks & Open Questions
1. **Spotlight won't index `.git`** → manual enumeration is the real source of truth (S4).
2. **libghostty API instability** → SwiftTerm for v1; libghostty is opt-in v2 (S7).
3. **Full Disk Access friction** → offer scoped-folder mode; explain why on first run (S8).
4. **Animated gradient vs terminal perf** → throttle/freeze gradient under load; Reduce Motion (S6).
5. **Right-arrow semantics** → must not hijack `→` for cursor movement mid-line; only accept at EOL (S2).
6. **Huge histories / monorepos** → paginate commits, cap revwalk, lazy worktree loading.
7. **Scope creep** → ship vertical slices (one project → tree → terminal) before breadth.

---

*Companion file: `CLAUDE.md` (project rules for Claude Code). Start with §4 spikes — do not skip them.*
