# Classic Native Boost + Assist V1 (Evade iOS / Delta)

**Independent experiment.** This is **not** PC Movement V3.1 or V3.2. It keeps the actual Roblox **Classic Thumbstick** (TouchThumbstick), its original graphics, touch area, camera handling, jump button, and PlayerModule control loop. It does not generate a second joystick.

## One-time setup

1. Select **Classic Thumbstick / Joystick Clássico**, not Dynamic Thumbstick, inside Roblox.
2. Remove/disable the previous **PC Movement AutoExecute** before using this. Do not run both.
3. Run this Lua code in Delta:

~~~lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/feature/mobile-classic-boost-assist-20261109/ClassicNativeBoostAssistLoader.lua", true))()
~~~

This is a **test build**. Its first print can say waiting-for-native-controls while the script locates the active controller. Inspect GetState() after the classic joystick has become visible and you have touched it.

## How it works

ClassicNativeBoostV1.lua wraps **only** the built-in Classic activeController:GetMoveVector() method if the older Roblox PlayerModule exposes it. The native controller still owns the touch input. Horizontal input is remapped symmetrically using an 8% start and 58% saturation point, with a normalized max-length vector. W/S (forward/back) is left analog and camera-relative by Roblox. A->D and D->A use the current input sample without any key latch or artificial hold. No key events, second Player:Move() call, cloned buttons, TouchGui.Enabled change, or WalkSpeed write.

This does **not** skip the time your real finger needs to pass through center, bypass the game's acceleration/physics, or guarantee physical turning in a single frame. The classic controller's own input deadzone occurs upstream and cannot be recovered just by remapping its output. The actual in-game benefit depends on the Evade mobile controls and engine.

ClassicNativeGridAssistV1.lua is an adapted version of the preserved V3.1 **light** grid Assist (contact observation + optional facing assistance). It uses the native Humanoid.MoveDirection rather than interpreting keyboard W/A/S/D, and never injects speed, force, upward impulses, or jump requests. It samples fences at up to 12 Hz with three ray heights, compared with 20 Hz/four heights in the original. It only helps avatar facing when native Humanoid.AutoRotate is already **off**; otherwise Roblox remains in charge to avoid tug-of-war. Its contact scanner is primarily diagnostic and **not a proven movement-speed aid**. The boost itself is the movement change to evaluate.

If Evade uses a different PlayerModule, the boost reports an unsupported/waiting status and leaves native movement unchanged. **Do not call it working solely because the loader printed "Loaded."**

## Controls / safe rollback

~~~lua
local m = getgenv().ClassicNativeBoostAssist
print(m.GetState().boost.status)          -- "active" = native Classic hook installed
m.SetBoost(false)                        -- pause boost; original native input
m.SetBoost(true)                         -- resume
m.SetLateral(0.08, 0.58)                 -- (start, full-strength point)
m.SetAssist(false)                       -- disable contact/facing Assist for FPS A/B
m.SetAssist(true)                        -- re-enable Assist
m.SetDiagnostics(true)                   -- extra Assist contact observations
m.ExportDiagnostics()                    -- JSON file, if writefile exists
m.Stop()                                 -- restore the exact original controller method
~~~

**Do not edit native Roblox PlayerModule files.** This wrapper restores the controller's prior method on stop. It will not forcibly undo a third party's later hook if another script replaces ours.

## On-device test checklist

- Verify GetState().boost.status == "active" with Classic selected. If it remains waiting-for-classic-thumbstick, check the game control setting and do not claim success.
- Start and end a touch: no drift, no ghost movement, no false X input.
- Swipe left -> right -> left horizontally, slowly and quickly. Compare with native baseline.
- Try W, S, W+A, W+D, A+S, S+D. The visuals and direction must remain natural.
- Jump, air-strafe, bhop, trimp, crouch, turn camera, touch right half, respawn. No behavior should be blocked or double-triggered.
- Compare FPS/micro-stutter with Assist on vs off. Contact scanning has a nonzero cost.
- Run m.Stop() and confirm the old joystick remains and the native response returns without restarting the game.

## Validation status

**Code and mathematical behavior only:** the reverse-direction sample model, zero-release behavior, saturation/symmetry, diagonal normalization, and source invariants are checked in tests/native-classic/test_contracts.py. The V3.1 preserved source files stay unchanged on their branch.

**Not yet validated:** execution in the actual Roblox iOS build, native controller identity in Evade, PlayerModule hot reload/alternate input systems, gameplay physics, objective A/D response timing, FPS, or the perception of faster turns.

This branch is intentionally separate from V3.1 preserved and from main.
