# PC movement rebuild implementation plan

> **For agentic workers:** Use superpowers:executing-plans for continuous inline implementation; independent historical audit and final whole-branch review only.

**Goal:** deliver one self-contained AutoExecute file, preserving the controls and replacing the movement motor with native keyboard inputs.

**Architecture:** Pure state/input core, one keyboard route, original presentation, passive contact sensor and one runtime/lifecycle owner.

**Tech Stack:** Roblox Luau; offline tests with Lua/Luau; Python standard-library bundle/check tools.

**Spec:** `docs/superpowers/specs/2026-11-01-pc-movement-rebuild-design.md`

## Global constraints

- No modifications to historical scripts; base ce4eb8b, new branch feature/pc-movement-rebuild-20261101.
- No writes to velocity/CFrame/forces/collision/movement properties; no artificial air hop.
- Exact standing ground chords W+A, W, W+D, S; all restricted movement modes A/D only.
- GUI names/assets/layout retained; no new visible panels; diagnostic logs disabled by default.
- Broad sensor queries bounded; proximity is never contact proof.

## Review focus

- Fast A/D switches and mode changes while a finger is held must never queue W or a neutral frame.
- Unknown crouch/emote state must be visible in diagnostics, not fabricated from animation posture.
- Missed key releases, app background, chat focus, death and respawn must not leave held keys.
- Old watchers, re-execution and overlay replacement must not spawn competing movement writers.
- Nearby decorative grids and cached contact must never enable a jump or alter velocity.

### Task 1: pure movement and jump core

**Files:** create `rebuild/Core.lua`, `tests/core_test.lua`.
**Interfaces:** `Core.new(config):step(input, observation, now)` produces keys/state; `Core.keys(send)` applies/retries delta events; `Core.jump(config)` manages one native Space owner.

- [x] Write behavioral tests for exact chords, A/D reversal, layered air/reverse/emote/grid flags, neutral/dead input, failure retry and native jump gate.
- [x] Run tests and observe missing-engine failure.
- [x] Implement production core; run tests until green.

### Task 2: native adapters and runtime

**Files:** create `rebuild/KeyboardRoute.lua`, `rebuild/Controls.lua`, `rebuild/GridSensor.lua`, `rebuild/CameraGate.lua`, `rebuild/Runtime.lua`, `tests/adapters_test.lua`, `tests/route_mobile_test.lua` and fixture utilities.
**Interfaces:** route `Start/Refresh/IsReady/Stop/GetState`; controls `new/Contains/SetKnob/Step/Stop`; grid `new/Bind/Sample/Stop`; runtime `Start(modules, config)` exports PCMovementRebuild API.

- [x] Add regressions for contact/proximity distinction, sensor ceiling, camera finger ownership, failed route, focus/death/restart, preservation of UI layout.
- [x] Observe failures, implement adapters, retain only original visual construction/layout and validated controller selection concepts.
- [x] Run complete offline suite; document unknown signals.

### Task 3: standalone delivery, verification and branch

**Files:** create `tools/build_rebuild.py`, `tools/check_rebuild.py`, `PC_Movement_Rebuild_AUTOEXECUTE.lua`, `PCMovementRebuildLoader.lua`, `REBUILD_README.md`, video/validation notes.
**Interfaces:** deterministic bundle contains the six factory modules; loader fetches only that bundle.

- [x] Test bundle completeness, no runtime HTTP in standalone, no physical property writes and no legacy-file changes.
- [x] Build, run complete suite, syntax compile all production modules/bundle, benchmark pure input loop.
- [x] Review whole branch, address substantive findings, record on-device test limits.
- [ ] Commit and push only the new branch; verify remote files/head; deliver one AutoExecute file and branch links.
