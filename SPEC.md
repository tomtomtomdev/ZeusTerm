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
```
Persisted **IndexEntry** (GRDB) holds `rootURL`, `lastScanned`, `headSHA` for fast incremental rescans.

---

## 7. UI / UX Spec

```
┌────┬───────────────────────────┬─────────────────────────────────────────┐
│ P  │  Repo Tree (Project A)    │   Terminal Sessions  [ zsh ][ +  ]        │
│ R  │  ▾ repo: app              │  ┌─────────────────────────────────────┐  │
│ O  │    ▾ worktree: main       │  │  (animated gradient background)     │  │
│ J  │      ▾ branch: main ●     │  │  $ git st▮atus      ← ghost text →   │  │
│ E  │          • a1b2c fix CI   │  │  ...                                │  │
│ C  │          • 9f3d add tests │  │                                     │  │
│ T  │    ▸ worktree: hotfix     │  └─────────────────────────────────────┘  │
│ S  │  ▸ repo: lib              │   cwd: ~/Projects/app  branch: main       │
└────┴───────────────────────────┴─────────────────────────────────────────┘
 ↑ project rail (side tabs)   ↑ 4-level tree           ↑ full terminal + gradient
```

- **Project rail (far left):** the "side tabs per project." Reorderable, pinnable, badge for dirty state.
- **Tree (middle):** Repo→Worktree→Branch→Commit, spring expand/collapse, dirty/ahead-behind badges.
- **Terminal (right):** session tab strip, gradient background, ghost-text input line.
- **Animations:** `matchedGeometryEffect` on tab/session moves; spring on tree; subtle gradient drift.
- **Theming:** gradient + font + color scheme per theme; live Settings preview.
- **Accessibility:** Reduce Motion, Increase Contrast (auto-boost text contrast over gradient), full keyboard nav, VoiceOver labels on tree + tabs.

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
| **P2 Domain + Git** | Entities, use cases, `ZeusGit` (libgit2 + worktree shell-out), unit tests | `clean-architecture`, `tdd-kent-beck` |
| **P3 Scanner** | `ZeusScanner` (FS+Spotlight+FSEvents), GRDB index, incremental rescan | `macos-development`, `xunit-test-patterns` |
| **P4 Tree UI** | Repo→Worktree→Branch→Commit view, animated, project rail | `swiftui-architecture` |
| **P5 Terminal** | SwiftTerm bridge, sessions, per-project inner tabs | `macos-development` |
| **P6 Autocomplete** | Suggestion engine + ghost text + `→` accept | `swiftui-architecture`, `clean-code` |
| **P7 Gradient/Theme** | Gradient engine, Settings live preview, presets | `swiftui-architecture` |
| **P8 Polish/Ship** | Perf, a11y, notarize/package, `/code-review` + `/security-review` | `refactoring-fowler`, `/security-review` |

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
