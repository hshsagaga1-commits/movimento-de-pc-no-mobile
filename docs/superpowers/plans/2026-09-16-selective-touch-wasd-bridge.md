# Selective Touch WASD Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the native fixed Roblox thumbstick and camera touch behavior, while converting only the joystick-owned movement intent into persistent keyboard semantics without relying on PreferredInput/controller switching for locomotion.

**Architecture:** Read the native touch controller's raw move vector before suppression, return zero to the native mobile movement path, and publish a digital 8-way intent through two decoupled outputs: persistent W/A/S/D key events for game keyboard semantics and an explicit camera-relative Player:Move call for reliable locomotion. Camera and non-joystick touches are not intercepted. The branch remains isolated from V614/main.

**Tech Stack:** Luau, Roblox PlayerModule/Controls, VirtualInputManager, RunService.

**Spec:** User-approved selective bridge: native classic joystick stays usable; only joystick movement is bridged; camera touch stays touch; no Camera.CFrame or HumanoidRootPart.CFrame writes.

## Global Constraints

- Do not modify V614, V604, main, camera CFrame, HumanoidRootPart CFrame, or physics.
- Keep native TouchGui and native classic thumbstick visible.
- Only the movement controller output is suppressed; camera touch remains untouched.
- Persistent chords must preserve keys that remain held (W -> W+D keeps W down).
- Cleanup must restore the original GetMoveVector and release all synthetic keys.

---

### Task 1: Selective native-thumbstick bridge

**Files:**
- Create: `ClassicJoystickSelectiveWASD.lua`

**Interfaces:**
- Consumes: `PlayerModule:GetControls()`, native touch controller `GetMoveVector`.
- Produces: `getgenv().PCSelectiveWASD`, `getgenv().__PCSelectiveWASDCleanup`.

- [ ] **Step 1: Establish a failing/static contract**

The implementation must contain a native-controller hook that captures the original move vector, returns `Vector3.zero` to the mobile movement path, emits persistent W/A/S/D keys, and calls `Player:Move` from the captured digital intent. It must not contain writes to `Camera.CFrame`, `HumanoidRootPart.CFrame`, or `TouchGui.Enabled=false`.

- [ ] **Step 2: Implement the minimal selective bridge**

Capture the original `GetMoveVector`, quantize independent X/Z axes with hysteresis, return zero from the hooked touch controller, emit only changed key states with `VirtualInputManager:SendKeyEvent`, and apply the same digital move vector explicitly after the normal input step with `player:Move(vector, true)`.

- [ ] **Step 3: Add lifecycle/cleanup**

Reacquire a replaced touch controller, keep TouchGui enabled/untouched, release keys when the native joystick returns to zero, and restore the exact original controller method on cleanup.

- [ ] **Step 4: Verify statically**

Fetch the committed file and verify: selective controller hook present; `Player:Move` present; persistent key transition logic present; no `Camera.CFrame`, `HumanoidRootPart.CFrame`, `TouchGui.Enabled=false`, or custom joystick GUI.

- [ ] **Step 5: Commit**

Commit only the new experiment and plan on `classic-wasd-experiment`. Runtime behavior still requires on-device validation in Delta/iPhone.
