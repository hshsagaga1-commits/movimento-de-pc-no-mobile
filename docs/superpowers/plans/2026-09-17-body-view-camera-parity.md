# Body View Camera Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Match the PC references more closely: low first-person leg visibility in Overhaul and pitch-dependent, closer third-person framing in Legacy.

**Architecture:** Replace the V1 backward-lookvector Overhaul offset and bounding-box Legacy zoom with two isolated presentation paths. Overhaul only controls local body visibility and a small vertical presentation offset. Legacy applies a bounded smooth pitch curve relative to native camera distance, never a fixed fit-to-avatar distance.

**Tech Stack:** Luau, Python numerical model tests.

**Spec:** `docs/superpowers/specs/2026-09-17-pc-mobile-parity-design.md`

## Global Constraints
- Do not change FOV.
- Do not change sensitivity or input routing.
- Do not move first-person camera backward from the head.
- Do not force third-person zoom when the user is in first person.
- Restore all local transparency/offset state on cleanup.

---

### Task 1: Pitch-distance curve tests

**Files:**
- Modify: `PCEvadeBodyViewV1.lua`
- Test: local Python numerical model (ephemeral)

- [ ] **Step 1: Write failing tests**
Model pitch samples: +35, 0, -30, -60, -85 degrees. Require correction to be near zero/highly close at +35/0, increase in the mid/downward range, then reduce again at -85. Require max added distance <= 2.2 studs.

- [ ] **Step 2: Run against old fit model**
Expected: fails because old model targets 6.8-9.2 studs independent of pitch.

- [ ] **Step 3: Implement a smooth curve**
Use piecewise smoothstep interpolation over pitch anchors; apply only positive bounded delta relative to the current/native third-person camera-to-subject distance. Preserve raycast collision clamp.

- [ ] **Step 4: Verify numerical tests**
Expected: monotonic segments match the reference shape, no discontinuity > 0.15 stud between adjacent 1-degree samples.

### Task 2: Overhaul first-person body presentation

- [ ] **Step 1: Write source-contract failing checks**
Assert new implementation must not contain `cf.Position-cf.LookVector*back` or any first-person backward zoom. Assert lower-body visibility names remain and a bounded vertical offset constant exists.

- [ ] **Step 2: Implement minimal presentation change**
Keep camera position from the game. Force lower-body LocalTransparencyModifier to 0 in first person. Apply a small downward subject/presentation offset only if a safe PlayerModule/BaseCamera hook is available; otherwise visibility-only fallback.

- [ ] **Step 3: Verify source contracts**
No backward zoom, no FOV writes, no movement imports, cleanup restores local modifications.

### Task 3: Independent body-view loader

**Files:**
- Create: `BodyViewLoader.lua`

- [ ] **Step 1: Write loader contract check**
Loader must fetch only `PCEvadeBodyViewV1.lua` and must not reference `PCModeLock`, joystick bridge, crouch helper, or sensitivity repo.

- [ ] **Step 2: Create minimal standalone loader**
Use a GUID cachebuster and execute body-view module only.

- [ ] **Step 3: Verify contract**
Expected: one fetch target, no unrelated module names.

- [ ] **Step 4: Commit**
Commit message: `feat: add pitch-aware Legacy framing and low Overhaul body view`.
