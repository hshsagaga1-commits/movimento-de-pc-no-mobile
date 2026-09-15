# V605 — Screen-Space / Native Chain Probe

## Validated base retained

V605 does not replace or re-open V604's multitouch ownership work. It loads the
published V604 unchanged and keeps its proved identity rules:

```text
joystick: active movement controller moveTouchObject == input
camera:   active BaseCamera fingerTouches[input] == false
```

The same real camera-owned Touch continues through V604's bookkeeping-preserving
`OnTouchChanged` pass and then `OnMouseMoved`. Unknown, conflicting, joystick,
and pinch inputs retain the V500 fail-open route.

The V604 relay still starts disabled on each load and can only be enabled after
the current session proves simultaneous joystick and camera ownership. V605's
mobile panel controls that existing relay; it does not add a new input route.

## Question measured by V605

V605 is deliberately observational. It does not claim that active mouse-lock or
`mouseLockOffset` alone reproduces PC framing. Its question is:

> Which native camera/control stage correlates with the stable PC-like
> screen-space composition, and which relationship is missing on Touch even
> when MovementRelative, camera mouse-lock state, shoulder offset, and the
> `OnMouseMoved` route are active?

To answer that without feeding a screen-position error back into the game, the
probe records the following after Roblox's camera update:

- camera yaw and pitch;
- HumanoidRootPart yaw and camera-to-root yaw difference;
- RootPart and torso projection through `Camera:WorldToViewportPoint()`;
- pixel and viewport-normalized RootPart span/drift;
- camera yaw travel versus root yaw travel;
- camera distance to RootPart and camera focus distance;
- active movement-controller move vector;
- `IsMoveVectorCameraRelative()` when exposed;
- `UserGameSettings.RotationType` and `MouseSensitivity` as observed state;
- `Humanoid.AutoRotate` as observed state;
- `Set/GetIsMouseLocked`, `Get/SetMouseLockOffset`, camera type and subject;
- pre-camera `rotateInput` and the native `GetMouseDelta()` reading.

The report separates samples taken with the V604 relay off and on. It also has
manual `PARADO`, `ANDANDO`, and `LIVRE` phases so motion-induced projection
changes are not silently mixed with stationary camera rotation.

## Touch versus Mouse-route scale

V605 polls the already-observed V604 event state and records only camera-owned
Touch events. It calculates the observed absolute coefficient:

```text
abs(rotateInput after - before) / abs(input.Delta)
```

separately for the original `OnTouchChanged` route and the V604 `OnMouseMoved`
route. This provides evidence for the reported heavier/slower camera without
changing gain, sensitivity, or physics. The report includes X/Y mean, minimum,
maximum, and Y/X ratio for each route.

This polling is capped at 20 Hz and may observe only the last input event in an
interval, so the coefficient data is a structural sample, not an exhaustive
event trace. The cap avoids repeatedly constructing V604's full diagnostics at
render frequency and contaminating the iPhone camera-performance measurement.

## Runtime PlayerModule chain discovery

At load, V605 recursively inspects the table/metatable/`__index` chains for:

- CameraModule;
- active camera controller;
- ControlModule;
- active movement controller.

Relevant method names, constants, and upvalues are recorded. Function-valued
upvalues are followed for up to three levels so helpers behind
`OnTouchChanged`, `OnMouseMoved`, camera translation, movement-relative, and
camera-relative paths can appear even when they are not direct table methods.

Selected methods are hooked observationally and always receive their original
`self` and arguments unchanged. Call counts distinguish, when Delta exposes
`checkcaller()`, executor-origin calls from game/CoreScript-origin calls. This is
particularly important because V500 itself sets the camera controller's logical
lock and offset each frame; those calls must not be mistaken for a missing
native PC stage.

Observed methods can include:

- `SetIsMouseLocked` / `GetIsMouseLocked`;
- `SetMouseLockOffset` / `GetMouseLockOffset`;
- `UpdateMouseBehavior` (observation only; never called by V605);
- `GetMoveVector` / `IsMoveVectorCameraRelative`;
- camera subject/look/distance helpers;
- relevant `Update` / `OnRenderStepped` stages.

## Mobile single-session test

Everything needed is displayed inside Roblox. Do not leave Roblox until the
final report has been copied.

1. Execute the normal cache-busting `Loader.lua` once. The V605 panel appears on
   the right and can be dragged or collapsed.
2. Tap **INICIAR MEDIÇÃO** while `RELAY V604` is still off.
3. In phase **PARADO**, drag the camera left/right and up/down without walking.
   This records the original Touch route scale.
4. Hold/move the joystick and drag the camera with another finger. This proves
   the V604 ownership gate for the current session.
5. Tap **RELAY V604: DESLIGADO**. It must change to **LIGADO**. If it is refused,
   repeat the simultaneous joystick + camera gesture and tap again.
6. Still in **PARADO**, repeat the same camera rotations, including a fast
   reversal and approximately 180 degrees.
7. Tap **FASE: PARADO** once to select **ANDANDO**. Hold the joystick while
   rotating the camera around the moving character, including looking from the
   side/back and walking over uneven ground if safe.
8. Optionally select **LIVRE** for steep pitch, zoom/pinch, and normal play.
9. Tap **PARAR MEDIÇÃO**, then **COPIAR REPORT**. Only after the panel confirms
   `REPORT COPIADO` should Roblox be left and the report pasted into ChatGPT.

The red **EMERGÊNCIA • VOLTAR AO V500** button stops measurement and disables
the V604 relay immediately. It does not require a console.

## How the next report should be interpreted

The most useful comparisons are:

- `relayOff*` versus `relayOn*` for screen drift and yaw response;
- `standing*` versus `moving*` to separate camera-only composition from normal
  character translation;
- `touchRoute*RadPerDelta*` versus `mouseRoute*RadPerDelta*` for the heavier
  camera report;
- `runtimeCallSummary` game calls versus executor calls;
- state transitions for RotationType, AutoRotate, mouse-lock, offset, and
  camera-relative movement;
- frame samples around high camera-yaw travel and visible RootPart screen drift.

V605 does not use those measurements to move the character or camera. A later
phase/version should only mutate one native state after the report demonstrates
which stage differs.

## Safety invariants

V605 itself adds no synthetic input, `firesignal`, VirtualInput call, reconnect,
`UpdateMouseBehavior()` call, Camera CFrame write, RootPart CFrame write,
AutoRotate write, sensitivity/gain adjustment, WalkSpeed/velocity/physics
change, half-screen rule, processed ownership gate, or screen-space correction.

V604 and V500 remain the functional/fail-open layers underneath. The inherited
V500 keyboard mirror is not extended or used by V605's probe.

`PCMovementV20_STABLE.lua` remains byte-identical with required SHA-256:

```text
634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef
```
