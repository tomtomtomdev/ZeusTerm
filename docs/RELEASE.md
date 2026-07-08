# Releasing Zeus (Developer ID + notarized)

Zeus ships as a **Developer ID-signed, notarized, non-sandboxed** macOS app (SPEC §8). This is the
one-time setup and the release flow. The heavy lifting is in [`scripts/notarize.sh`](../scripts/notarize.sh).

## What P8-F put in place
- **Hardened Runtime** is on (`ENABLE_HARDENED_RUNTIME = YES`) — required for notarization.
- **App Sandbox** stays off (`ENABLE_APP_SANDBOX = NO`) — full-disk scanning + `git` shell-out are core.
- **Entitlements:** [`Zeus/Zeus/Zeus.entitlements`](../Zeus/Zeus/Zeus.entitlements) — minimal
  (sandbox off, no JIT/library-validation exceptions). Zeus spawns the system `/bin/zsh` (PTY) and
  `/usr/bin/git` as child processes, which Hardened Runtime allows without extra entitlements, and it
  statically links SwiftTerm/GRDB into the signed app, so library validation stays on.
- **Privacy manifest:** [`Zeus/Zeus/PrivacyInfo.xcprivacy`](../Zeus/Zeus/PrivacyInfo.xcprivacy) — no
  tracking, no data collection; declares the scanner's file-timestamp reads (reason `C617.1`).
- **Shared scheme:** `Zeus.xcodeproj/xcshareddata/xcschemes/Zeus.xcscheme` so CI/scripts resolve
  `-scheme Zeus`.
- **Bundle id:** `com.zeusterm.Zeus` (was the placeholder `com.tom.tom.tom.Zeus`). Change it to your
  own reverse-DNS id if you prefer.

## One-time credential setup
1. A **Developer ID Application** certificate in your login keychain (Xcode ▸ Settings ▸ Accounts ▸
   Manage Certificates, or from developer.apple.com).
2. A **notarytool keychain profile** with an app-specific password:
   ```sh
   xcrun notarytool store-credentials ZeusNotary \
     --apple-id "you@example.com" --team-id "ABCDE12345" \
     --password "<app-specific-password>"   # create at appleid.apple.com ▸ App-Specific Passwords
   ```

## Cutting a release
```sh
TEAM_ID=ABCDE12345 scripts/notarize.sh
```
It archives → exports a Developer ID app → submits to the notary service (`--wait`) → staples the
ticket → validates. The finished app lands at `build/export/Zeus.app`. Verify Gatekeeper with:
```sh
spctl -a -vvv --type execute build/export/Zeus.app
```

Then package the stapled app into a distributable disk image (drag-to-`/Applications` layout,
`hdiutil`-only — no Homebrew dependency):
```sh
scripts/make-dmg.sh                                   # → build/Zeus-<version>.dmg
TEAM_ID=ABCDE12345 NOTARIZE_DMG=1 scripts/make-dmg.sh # also notarizes + staples the dmg itself
```

## ⚠️ Host requirement / deployment-target divergence
- The **app target** is `MACOSX_DEPLOYMENT_TARGET = 26.2`; the **ZeusKit package** floor is
  `macOS 15`. So the SPM unit tests (`swift test`) run on any recent Mac, but **archiving/running the
  app requires a macOS 26 host** with the matching SDK. This is why the precommit gate skips
  `xcodebuild test` on older hosts, and why `/verify` of the running app must happen on a macOS 26
  machine.
- **Option worth considering:** the entire `ZeusUI` layer already compiles at the macOS 15 floor, so
  if nothing in the thin app target genuinely needs a macOS 26-only API, lowering the app's
  deployment target toward the package floor would let the app build, run, and be `/verify`-ed on
  macOS 15 hosts. Left unchanged here — it's a product decision about the minimum supported OS.
