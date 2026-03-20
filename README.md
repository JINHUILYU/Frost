# FrostBar

FrostBar is a macOS menu bar item manager built from scratch with a hybrid architecture:

- Swift/AppKit shell for UI and macOS system integration
- Objective-C++ bridge for cross-language boundaries
- C++ core for layout rules, policies, and testable business logic

## Current status

- C++ core layout engine scaffold is implemented and buildable.
- Objective-C++ bridge API scaffold is implemented.
- Swift shell is currently a placeholder entry point.
- This repository is in scaffold stage, not feature-complete MVP.

## Why hybrid instead of pure C++

On macOS, menu bar APIs, event taps, permissions, and runtime integration are native to AppKit and Objective-C runtime. A pure C++ implementation is not practical for full product behavior. Hybrid keeps platform integration robust while preserving C++ where it adds the most value.

## Project layout

- `app-swift`: Swift app shell and menu bar interaction
- `bridge-objcxx`: Objective-C++ bridge between Swift and C++
- `core-cpp`: Pure C++ domain logic
- `docs`: Architecture and implementation notes
- `scripts`: Setup scripts

## Quick start

1. Configure and build core:

```sh
cmake -S . -B build
cmake --build build
```

1. Run tests:

```sh
ctest --test-dir build --output-on-failure
```

1. Optional: run scaffold bootstrap script only when you want it to auto-create an initial commit in a fresh clone:

```sh
bash scripts/bootstrap.sh
```

Note: the bootstrap script runs git add . and may create a commit automatically.

## Minimal app preview and DMG

1. Build a minimal menu bar app bundle:

```sh
bash scripts/build_app.sh
```

1. Package a DMG from the generated app:

```sh
bash scripts/package_dmg.sh
```

1. Run preview app:

```sh
open build/app/FrostBar.app
```

## Scope for MVP

- Discover and represent menu bar item metadata
- Define visibility/layout rules in C++
- Apply hide/show through macOS shell layer
- Revert state safely when app exits

See `TASKS.md` for phased implementation tasks.
