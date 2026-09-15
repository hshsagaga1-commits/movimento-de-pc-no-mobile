# V600 — Decoupled Native Mouse Path

## Why this experiment exists

The supplied PC clips show a continuous centered camera stream while the avatar can keep moving independently and be viewed from the front, back, or side. The mobile comparison shows:

- V15/V18 established the correct native movement foundation.
- V19 is visibly too rigid because orientation is hard-locked.
- V23/V25 change ratios or touch math, but still behave like touch orbit.
- V26 reaches the Legacy `MouseMovement` callback, but also enables the normal shift-lock character coupling.
- V500 removes most of that coupling with `MovementRelative`, but leaves the native touch-pan path in charge of rotation.

V600 isolates the missing test: reuse V26's proven Legacy mouse callback while keeping V500's decoupled character/movement state.

## Architecture

`PCMovementV600_DecoupledNativeMouse.lua` loads V500, which already contains the V20/V18/V15 foundation. It then:

1. identifies the exact `UserInputService.InputChanged` callback owned by the active Legacy camera controller;
2. lets Roblox process the real touch packet for touch bookkeeping and pinch lifecycle, with only one-finger pan temporarily suppressed;
3. replays that packet to the same callback as `MouseMovement`;
4. reports the viewport center as `Position` and the measured/calibrated relative delta as `Delta`;
5. keeps `RotationType` at `MovementRelative` before and after the replay.

The implementation deliberately does not call `UpdateMouseBehavior()`. It also does not write `Camera.CFrame`, `Camera.Focus`, `HumanoidRootPart.CFrame`, `WalkSpeed`, velocity, or `Humanoid.AutoRotate`.

## Fail-open behavior

V600 leaves V500 active as its fallback. It automatically stops replacing touch pan when:

- `getconnections` or `hookfunction` is unavailable;
- the camera callback cannot be tied to the active controller with a safe score;
- three callback errors occur; or
- twelve non-zero mouse packets leave the Legacy controller's `rotateInput` unchanged.

This prevents an unsupported executor/client build from leaving the camera unusable.

## Runtime switches and diagnostics

```lua
getgenv().PCV600MouseRelayEnabled=false -- immediate V500 touch-camera fallback
getgenv().PCV600MouseRelayEnabled=true  -- enable relay again after re-running Loader

getgenv().PCV600MouseGainX -- calibrated horizontal gain
getgenv().PCV600MouseGainY -- calibrated vertical gain

getgenv().PCV600Report() -- prints a readable report in the executor console
```

The first comparison should keep the default gains. V600 is intended to test input semantics without mixing in another sensitivity experiment.

## Device test matrix

Record one continuous clip containing:

1. hold forward and rotate the camera about 180 degrees;
2. make two fast left-right camera reversals;
3. move diagonally while rotating through the avatar's front and side;
4. use steep up/down and top-down angles;
5. pinch zoom, jump, crouch, ragdoll, and one emote.

Success requires all of the following:

- `bridgeMode` becomes `decoupled-native-camera-mousemovement`;
- `relayedEvents` increases and `autoDisabled` remains false;
- the avatar remains movement-relative rather than camera-relative;
- zoom, collision, jump, crouch, ragdoll release, and emote zero-offset remain native;
- reversals and long turns look less like discrete touch-orbit grabs than V500.

The repository cannot execute an iPhone Roblox/Delta session, so behavior beyond static validation remains a device-test result. The supplied videos establish that V500 improved decoupling over V26; V600 is the controlled experiment for the remaining input-path mismatch.

## Rollback

- Stable file: `PCMovementV20_STABLE.lua` (must remain unchanged).
- Stable loader: `LoaderV20Stable.lua`.
- Previous experiment: `PCMovementV500_ScrapFusion.lua`.
