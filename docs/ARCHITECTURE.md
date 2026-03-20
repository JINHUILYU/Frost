# Architecture

## Overview

FrostBar follows a 3-layer architecture:

1. Swift/AppKit shell: platform APIs, permissions, event taps, menu bar control.
2. Objective-C++ bridge: language boundary and lifecycle ownership.
3. C++ core: deterministic business logic with unit tests.

## Data Flow

1. Shell collects menu bar runtime snapshot.
2. Snapshot is converted in bridge to C++ structs.
3. C++ computes desired visibility and ordering.
4. Shell applies result and persists policy state.

## Ownership Rules

- Swift owns UI lifecycle and app state.
- Bridge owns transient object conversion only.
- C++ owns layout decisions and pure rules.

## Risk Notes

- Some menu bar behavior may rely on private runtime details.
- Every hide/show action should be reversible.
- State recovery after crash is required before public release.
