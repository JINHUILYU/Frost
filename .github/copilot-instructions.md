# Copilot Instructions

## Response Language

- Default to Chinese in responses.
- If the user explicitly asks for another language, follow the user's request.

## Build, Test, and Packaging Commands

- Full pipeline (logic tests + build + sign + DMG + verification):
  - `bash scripts/package_and_test.sh`

- Run the logic test target only:
  - `mkdir -p build/tests && swiftc app-swift/Sources/App/VisibilityStore.swift tests/visibility_store_test.swift -o build/tests/visibility_store_test && build/tests/visibility_store_test`

- Build only the app executable:
  - `mkdir -p build/app && swiftc app-swift/Sources/App/main.swift -o build/app/Frost -framework AppKit`

- No standalone lint command is configured in this repository.

## High-level Architecture

- The app is a macOS menu bar utility built directly with `swiftc` + `AppKit` (no Xcode project / SwiftPM manifest in repo).
- Main runtime orchestration is in `app-swift/Sources/App/main.swift`:
  - status item/menu lifecycle
  - running app discovery and filtering
  - multi-step app activation/reopen fallback
  - dynamic Settings window rendering
- Visibility persistence uses `UserDefaults` key `Frost.HiddenBundleIDs` via `VisibilityStore`.
- Packaging and release flow is script-driven in `scripts/package_and_test.sh`:
  - compiles tests and app
  - assembles `.app` + `Info.plist`
  - builds icon from `Frost.jpeg`
  - signs app, creates DMG, mounts DMG for verification
  - outputs `dist/Frost.dmg`

## Key Repository Conventions

- Running app list is intentionally filtered:
  - include `.regular` apps by default
  - include `.accessory` apps only when usable (visible window or allow-keyword match: `uu`, `quark`, `v2ray`, `wechat`, `tencent`)
  - exclude helper/service-like processes via keyword and fixed bundle ID denylist
- App activation is layered, not one-shot:
  - rank/select best running instance
  - retry by PID
  - AppleScript `activate`
  - conditional AppleScript `reopen` for specific families (Quark/WeChat)
  - final fallback via `NSWorkspace.openApplication`
- Menu and settings are regenerated dynamically using stable item tags (`dynamicItemTag`, `emptyItemTag`, `settingsItemTag`) to protect static controls.
- Visibility toggle UX is “Show in list”, but persistence model stores hidden bundle IDs (inverse mapping).
- Packaging script rotates previous artifacts into `delete/` with timestamps before replacing outputs.
