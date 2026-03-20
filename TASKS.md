# FrostBar Tasks

Updated: 2026-03-20

Detailed verification results: see TASKS_TEST_RESULTS.md

## Phase 0: Foundation

- [ ] Initialize repository, license, and CI
- [x] Define module boundaries (Swift shell, ObjC++ bridge, C++ core)
- [ ] Set coding conventions and error logging strategy
- [x] Add baseline smoke build for C++ core on macOS CI

## Phase 1: C++ Core Domain Model

- [x] Define menu bar item model (identifier, owner app, width, pinnedVisible, pinnedHidden)
- [x] Implement deterministic layout engine API
- [x] Add policy layer (always hidden, always shown, auto rehide)
- [x] Add unit tests for core rules and edge cases

## Phase 2: Bridge Layer

- [x] Add stable C/ObjC-facing API for C++ core
- [x] Implement conversion between Swift/ObjC models and C++ structs
- [ ] Add thread-safety guarantees for bridge calls
- [ ] Add contract tests for bridge marshaling

## Phase 3: Swift/AppKit Shell (MVP)

- [x] Create status item controller and runtime manager
- [ ] Discover menu bar items and map identifiers
- [ ] Apply hide/show actions with rollback support
- [ ] Add simple settings UI for visibility rules

## Phase 4: Interaction and Automation

- [ ] Add trigger conditions: hover reveal, click reveal, timed rehide
- [ ] Add global hotkey actions
- [ ] Add launch-at-login and startup restore
- [ ] Handle permission checks and failure UX

## Phase 5: Reliability and Productization

- [ ] Add crash-safe recovery for modified menu bar states
- [ ] Add structured telemetry/logging (local only)
- [ ] Test across macOS versions and notch/non-notch devices
- [ ] Package notarized release with update channel

## Non-Goals for MVP

- [ ] Visual customization themes
- [ ] Widget-like menu bar plugins
- [ ] Cross-platform support

## Completion Records

- [x] 2026-03-20: Define module boundaries
  Evidence: app-swift, bridge-objcxx, core-cpp modules and docs/ARCHITECTURE.md are present.
  Verification: structure and architecture file check passed.

- [x] 2026-03-20: Baseline smoke build for C++ core on macOS CI
  Evidence: .github/workflows/ci.yml configures and builds with CMake.
  Verification: local CMake build executed successfully.

- [x] 2026-03-20: Define menu bar item model
  Evidence: core-cpp/include/frostbar/MenuItem.hpp fields are defined.
  Verification: compiled and covered by core smoke tests.

- [x] 2026-03-20: Implement deterministic layout engine API
  Evidence: core-cpp/include/frostbar/LayoutEngine.hpp and core-cpp/src/LayoutEngine.cpp.
  Verification: deterministic decisions verified by tests.

- [x] 2026-03-20: Add policy layer (always hidden, always shown, auto rehide)
  Evidence: core-cpp/include/frostbar/PolicyEngine.hpp and core-cpp/src/PolicyEngine.cpp.
  Verification: policy precedence and rehide behavior verified by tests.

- [x] 2026-03-20: Add unit tests for core rules and edge cases
  Evidence: tests/core_smoke_test.cpp.
  Verification: CTest run passed.

- [x] 2026-03-20: Add stable C/ObjC-facing API for C++ core
  Evidence: bridge-objcxx/include/FrostBarBridge.h.
  Verification: interface presence and signature checks passed.

- [x] 2026-03-20: Implement conversion between Swift/ObjC models and C++ structs
  Evidence: bridge-objcxx/src/FrostBarBridge.mm conversion loops for input/output.
  Verification: source inspection checks passed.

- [x] 2026-03-20: Create status item controller and runtime manager (minimal preview)
  Evidence: app-swift/Sources/App/main.swift creates NSStatusItem and menu runtime.
  Verification: open build/app/FrostBar.app and AppleScript quit check passed.

- [x] 2026-03-20: Discover menu bar candidate apps (preview listing)
  Evidence: app-swift/Sources/App/main.swift refreshes and renders running accessory/prohibited apps.
  Verification: click status item icon and observe dynamic app list under icon.
