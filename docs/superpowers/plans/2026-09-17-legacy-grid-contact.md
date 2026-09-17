# Legacy Grid Contact Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make mobile maintain reasonable contact with Legacy grids/surfaces the way PC input does, without injecting an arbitrary speed boost.

**Architecture:** First ship a diagnostic that records command, movement, velocity, camera vectors, surface normal, distance, and speed trend. Then implement a conservative contact assist that preserves tangent velocity and restores only a small inward normal component while a verified nearby surface exists and the user is not commanding away from it.

**Tech Stack:** Luau, Workspace raycasts, Python vector model tests.

**Spec:** `docs/superpowers/specs/2026-09-17-pc-mobile-parity-design.md`

## Global Constraints
- Legacy place only (`96537472072550`).
- No direct `AssemblyLinearVelocity += ...` speed boost.
- Assist must be contact-gated and disengage immediately on away input/no hit.
- All movement chords are eligible when geometry supports contact.
- Crouch is observed, not overridden.

---

### Task 1: Diagnostic module

**Files:**
- Create: `LegacyGridProbeV1.lua`
- Create: `GridProbeLoader.lua`

- [ ] **Step 1: Write source-contract failing checks**
Require report fields for chord, MoveDirection, velocity, speed, camera look/right, ray hit normal/distance, crouch observation, and speed trend.

- [ ] **Step 2: Implement probe**
Sample at render/heartbeat cadence for a bounded run. Raycast around the root in commanded/camera-relative directions, choose the nearest plausible vertical surface, and append compact samples. Store report in `getgenv().LegacyGridProbeReport` and clipboard when available.

- [ ] **Step 3: Verify loader isolation**
`GridProbeLoader.lua` fetches only `LegacyGridProbeV1.lua`.

### Task 2: Vector assist model

**Files:**
- Create: `LegacyGridContactAssistV1.lua`
- Create: `GridAssistLoader.lua`
- Test: local Python vector model (ephemeral)

- [ ] **Step 1: Write failing vector tests**
Cases: tangent command on wall gains a small inward component; away command gets no assist; no hit gets no assist; diagonal command preserves tangent direction; opposite wall normals produce symmetric results; assist magnitude is capped.

- [ ] **Step 2: Run tests without implementation**
Expected: fail because assist function is absent.

- [ ] **Step 3: Implement minimal assist math**
For normalized command `d` and wall normal `n`, compute `normalDot=d:Dot(n)`. Never modify commands with `normalDot>awayThreshold`. Preserve tangent `d-n*normalDot`; if contact is verified and inward pressure is too small, add only `-n*PRESSURE_MIN`, normalize/cap, then feed through the existing movement path rather than directly adding world velocity.

- [ ] **Step 4: Verify model tests**
Expected: all geometry tests pass and no output magnitude exceeds 1.

- [ ] **Step 5: Implement Legacy integration**
Attach after digital chord selection, compute camera-relative intended world direction, raycast for nearby vertical surface, and bias the movement command only during verified contact. Expose diagnostics counters and cleanup.

- [ ] **Step 6: Static safety checks**
Assert no code assigns/adds to `AssemblyLinearVelocity`, `Velocity`, `CFrame` for boosting, and no Overhaul/global input spoof imports exist.

- [ ] **Step 7: Commit**
Commit message: `feat: add Legacy grid contact probe and conservative assist`.
