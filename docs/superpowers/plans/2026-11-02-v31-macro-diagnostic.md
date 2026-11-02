# V3.1 Macro Conflict Diagnostic Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a separate, reversible input trace for the obfuscated Evade macro and working V3.1, without changing controls.

**Architecture:** One optional Luau probe listens to UserInputService input phases and samples the existing bridge state. It records topmost PlayerGui objects under touch beginnings, keeps a bounded local ring, and exposes manual mark/copy/stop functions; a separate loader loads it only when requested.

**Tech Stack:** Luau, Roblox client APIs, existing offline Luau fixture and Python check runner.

**Spec:** `docs/V31_MACRO_PROBE_SPEC.md`

## Global Constraints

- Preserve every existing file from commit `a48741ca0f7b86f7a2c2631778ee5a86691b180f` byte for byte.
- Never load/modify MEMEDASH diagnostics or edit the external obfuscated macro.
- No virtual input, input blocking, global hooks, gameplay/UI/physics changes, or per-frame work.
- Only report input delivered to supported observers, never infer a hidden macro handler from timing alone.

## Review Focus

- A second finger on the camera must not be mistaken for the joystick finger: test identity correlation using the bridge's actual `movementTouch` object.
- A touch that begins over another GUI must preserve the topmost object's path in the report: test two GUI layers.
- A virtual key and mouse click may interleave around the same touch: test event order and timestamps without synthesizing inputs.
- Excessive touch moves must not grow memory unbounded: test throttling and ring capacity.
- Reexecution and Stop must disconnect every listener without altering the base controls: test idempotent cleanup.

---

### Task 1: Read-only input probe

**Files:** Create `PCMovementV31MacroConflictProbe.lua`, `tests/v31-macro-probe/diagnostic_test.lua`, `tools/check_v31_macro_probe.py`.

**Interfaces:** `getgenv().PCMovementV31MacroProbe.{Mark(label),GetReport(),CopyReport(),GetState(),Stop()}`; cleanup in `getgenv().__PCMovementV31MacroProbeCleanup`.

- [x] Write a Luau test using the existing fixture: two finger identities, layered UI hit testing, W/A/S/D/Space, mouse button, bounded touch changes, report order and Stop/reload; expect failure because the probe file/API is absent.
- [x] Run the new Luau test and inspect the expected missing probe failure.
- [x] Implement the separate listener and bounded report with only read-only APIs; annotate that synthetic/physical origin is not observable and `Mark` is manual.
- [x] Run the new test, the existing UI/Assist regression suite, Luau compilation and byte-invariance check; fix only failures introduced here.
- [x] Commit the tested probe and fixtures.

### Task 2: Optional loader and usage

**Files:** Create `PCMovementV31MacroProbe_AUTOEXECUTE.lua`, `V31_MACRO_PROBE_README.md`.

**Interfaces:** cache-busting `loadstring(game:HttpGet(...))()` targeting only the new probe; no dependency on or mutation of the V3.1 loader.

- [x] Add test assertion for loader URL and reexecution cleanup; observe failure before creating the loader.
- [x] Add the one-line loader and usage instructions: start usual joystick and macro, run probe, reproduce, mark/copy, Stop, send report.
- [ ] Verify published tree against local tree, run full checks and publish a new branch from the V3.1 visual fix commit; keep original branches untouched.
