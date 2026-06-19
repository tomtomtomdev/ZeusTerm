# Zeus — Project Instructions for Claude Code

Native macOS terminal + project navigator. Autoscans all git projects on the Mac and presents
them as **Repo → Worktree → Branch → Commits**, with an embedded full PTY terminal, right-arrow
autocomplete, per-project side tabs, and a configurable animated gradient background.

Read `SPEC.md` for the full product/technical spec and the §4 research spikes. **Do the spikes
before building features that depend on them.**

## Workflow — TDD is mandatory (non-negotiable)

**Every new feature is built test-first.** No production code for a new feature is written
before a failing test exists for it. Follow Kent Beck's Red → Green → Refactor on every cycle:

1. **RED** — invoke **`tdd-kent-beck`**, write the smallest failing test that states the next
   bit of behavior, and run it to confirm it fails for the right reason.
2. **GREEN** — write the minimum code to make it pass. Nothing more.
3. **REFACTOR** — clean up with tests green (`clean-code` / `refactoring-fowler`), re-run.

Rules:
- Start the RED step **before** writing implementation. If you catch yourself coding first, stop
  and write the test.
- Domain + use cases: pure unit tests (Swift Testing / XCTest). Adapters (git, scanner): fixture
  tests (use `xunit-test-patterns` for doubles/fixtures). UI flows: `xcui-automation-testing`.
- PTY/terminal interactivity and right-arrow accept can't be fully unit-tested — cover the logic
  with tests, then prove behavior with `/verify` in the running app.
- A feature is not "done" until its tests are committed alongside it (see Definition of done).
- Exceptions (throwaway spikes in §4 of SPEC, pure config) must be called out explicitly; default
  is always TDD.

## Workflow — Bug fixes (run tests first)

**Always run the test suite before touching code to fix a bug.** Never start editing on a hunch.

1. **Run tests first** (`swift test` / `xcodebuild test`) to capture the current green/red baseline.
2. **Reproduce with a failing test** — write a characterization test that fails because of the bug
   (invoke `tdd-kent-beck`; for gnarly untested code use `legacy-code` to find a seam first).
3. **Fix** until that test goes green, with the rest of the suite still green.
4. Keep the new test — it's the regression guard. Then `/verify` in the app if behavior is UI/PTY.

This means a real reproduction exists before the fix, and we know nothing else broke.

## Workflow — Refactoring (always Fowler)

**Always invoke `refactoring-fowler` when refactoring.** Refactoring = changing structure without
changing behavior, so:
- Tests must be **green before and after** — refactor only on a green bar (run them first).
- Name the smell and the named refactoring (Extract Function, Move Method, Replace Conditional
  with Polymorphism, etc.) from the catalog before applying it.
- Two-hats rule: never add behavior while refactoring; switch hats deliberately. Use preparatory
  refactoring ("make the change easy, then make the easy change").
- Use `/simplify` for reuse/efficiency passes once a feature lands.

## Stack
- Swift 6.2 (strict concurrency), SwiftUI + AppKit bridges. Target **macOS 26**.
- Terminal: **SwiftTerm** (PTY). Git reads: **SwiftGitX/SwiftGit2** (libgit2). Worktrees: **`git` CLI shell-out**.
- Discovery: FileManager + NSMetadataQuery + FSEvents. Persistence: SwiftData (settings) + GRDB/SQLite (index).
- Distribution: Developer ID + notarized, non-sandboxed (v1). Full Disk Access on first run.

## Architecture (enforce the dependency rule)
- `ZeusDomain` — entities + use-case protocols. **No framework imports.** 100% unit-tested.
- `ZeusGit` / `ZeusScanner` / `ZeusTerminal` / `ZeusSuggest` — adapters implementing domain ports.
- `ZeusUI` — SwiftUI views + `@MainActor @Observable` stores (UDF). `Zeus` app target = composition root.
- Off-main work (scan, git, suggest) lives on **actors**; never block `@MainActor`.

## Conventions
- Follow the `clean-code` + `swiftui-architecture` skills. Small functions, intention-revealing names.
- No god ViewModels — feature stores, value-type state, derive don't duplicate.
- Use `Glob`/`Grep`/`Read`/`Edit` tools, not bash equivalents (see global rules).
- Match surrounding style; keep comments at the density of nearby code.

## Skill triggers (BLOCKING — invoke BEFORE responding)

When a user prompt matches a row below, **invoke the listed skill via the Skill tool first**,
then act. This is a hard requirement, not a suggestion. If several match, invoke each relevant
one. Never just *mention* a skill — actually call it. Match on intent, not exact words; the
example phrases are illustrative.

| If the user asks about / says… | Invoke |
|---|---|
| anything Swift, SwiftUI, AppKit, Xcode, build, run, package, notarize, entitlements, sandbox; "build the app", "make a window", "add a view", "why won't it compile" | **`macos-development`** |
| app structure, state, `@Observable`/`@State`/`@Environment`, navigation, "how should I architect this screen", "where does this state live", god ViewModel, modularize | **`swiftui-architecture`** |
| layers, boundaries, dependency rule, ports/adapters, "where does this logic go", "is this coupled", domain vs infrastructure | **`clean-architecture`** |
| "review this code", "is this clean", naming, code smell, readability, "improve this function" | **`clean-code`** |
| "refactor this", "restructure", "clean this up without changing behavior", specific Fowler refactorings | **`refactoring-fowler`** |
| "this code has no tests", "make it testable", break a dependency, characterization tests, seams | **`legacy-code`** |
| "write tests", "test-first", "TDD this", "where do I start testing", red-green-refactor | **`tdd-kent-beck`** |
| test doubles (mock/stub/spy/fake), fixtures, "tests are brittle/duplicated", `XCTestExpectation`, async tests, fixture repos for git/scanner | **`xunit-test-patterns`** |
| "UI test", "tap a button in a test", XCUITest, element queries, end-to-end flow (open project → tree → terminal) | **`xcui-automation-testing`** |
| networking, fetch a URL, REST/JSON, remote git status, update-check, `URLSession`/`URLRequest` | **`urlsession`** |
| open research question (Spotlight `.git` indexing, libghostty viability, "research X") | **`deep-research`** |

### Slash commands (invoke when intent matches, even if not typed literally)
| Intent | Command |
|---|---|
| "run the app", "launch it", "screenshot it" | **`/run`** |
| "does this actually work", "verify the fix", "confirm terminal/right-arrow works" | **`/verify`** |
| "review my changes", "review the diff/PR" before merge | **`/code-review`** |
| anything touching scan / Full Disk Access / `git` shell-out / PTY surface | **`/security-review`** |
| "simplify this", reuse/efficiency cleanup after a feature lands | **`/simplify`** |
| too many permission prompts during `git`/`swift build` loops | **`/fewer-permission-prompts`** |
| set up / regenerate this file | **`/init`** |

> Default pairing: most build prompts trigger **`macos-development`**; design prompts add
> **`swiftui-architecture`** + **`clean-architecture`**; test prompts add the testing skills.

## Build / Run / Test
```bash
# generate/open (adjust once project layout exists)
xcodebuild -scheme Zeus -configuration Debug build
xcodebuild -scheme Zeus test
swift test            # for the SPM packages (ZeusDomain etc.)
```
Use `/run` to launch the app and `/verify` to confirm terminal interactivity (vim/htop) and
right-arrow accept actually work — UI/PTY behavior is not provable by unit tests alone.

## Guardrails
- **Security review the scan + shell-out + Full Disk Access surface** (`/security-review`).
  Never run untrusted repo hooks; sanitize paths passed to the `git` CLI.
- Don't eagerly walk full git history — paginate commits, lazy-load worktrees.
- Don't let the animated gradient starve the terminal — throttle under load; honor Reduce Motion.
- Only accept the `→` autocomplete suggestion when the caret is at end-of-line.
- Confirm before destructive git operations; Zeus is a navigator, not an auto-committer.

## Definition of done (per feature)
Test written first (RED→GREEN→REFACTOR) and committed with the code • full suite green •
builds clean • `/code-review` clean • `/verify` passes in the running app • honors Reduce Motion
+ accessibility • no `@MainActor` blocking. Bug fixes additionally ship the failing-then-passing
regression test.
