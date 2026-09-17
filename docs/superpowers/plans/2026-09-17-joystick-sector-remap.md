# Joystick Sector Remap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make W narrower, WA/WD larger, and preserve strong A/D digital access without the lateral latch swallowing diagonal sectors.

**Architecture:** Keep the existing V5.9 patching approach. Change only the sector classifier and latch scope. Validate with a pure Python behavior model before updating Lua.

**Tech Stack:** Luau, Python model tests, GitHub contents API.

**Spec:** `docs/superpowers/specs/2026-09-17-pc-mobile-parity-design.md`

## Global Constraints
- Existing 200 ms jump burst unchanged.
- Full digital movement only.
- No camera/body/grid imports.
- Recenter clears latch.

---

### Task 1: Red-green sector classifier

**Files:**
- Modify: `PCKeyboardTouchBridgeV5_9.lua`
- Test: local Python model script (ephemeral)

**Interfaces:**
- Consumes: normalized joystick x,z and existing `PRESS_THRESHOLD`.
- Produces: key set `{W,S,A,D}`.

- [ ] **Step 1: Write failing model tests**

```python
cases = {
  (0.00,-1.00): {'W'},
  (0.18,-1.00): {'W'},
  (0.35,-1.00): {'W','D'},
  (0.70,-1.00): {'W','D'},
  (1.00,-0.35): {'D'},
  (-0.35,-1.00): {'W','A'},
  (-1.00,-0.35): {'A'},
}
```
Also assert that a side sweep A->D does not pass through W, but explicit re-entry from center can reach WA/WD.

- [ ] **Step 2: Run the old classifier model**
Expected: at least the new W/diagonal boundary tests fail.

- [ ] **Step 3: Implement minimal classifier**
Use absolute angular/ratio thresholds equivalent to a narrow center W band and larger diagonal sectors. Restrict A/D latch to side-dominant entry and release it before the diagonal transition band.

- [ ] **Step 4: Run all model tests**
Expected: all cases pass, including dry A<->D and recenter access to diagonals.

- [ ] **Step 5: Update Lua source**
Replace only the sector constants/classifier block and version string. Do not touch jump code.

- [ ] **Step 6: Source contract checks**
Assert file still contains `JUMP_BURST_SECONDS=0.200`, no camera imports, and the new thresholds/version.

- [ ] **Step 7: Commit**
Commit message: `feat: narrow W and expand diagonal joystick sectors`.
