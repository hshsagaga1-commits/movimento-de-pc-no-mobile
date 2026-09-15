# V601 — Legacy Callback Discovery Probe

## Test result that triggered this build

The real Delta V600 report showed `discoveryScore = 0`, `callbackHooked = false`, and
`relayedEvents = 0`. V600 therefore never tested the decoupled MouseMovement path;
the recorded behavior was V500 fallback.

V601 does not change gain, sensitivity, movement, or physics. Its only job is to
identify and reach the Legacy camera `InputChanged` stage with enough evidence to
tell exactly where Delta allows or blocks the route.

## Primary V600 discovery defect

V600 compared connection wrappers through `Connection`, `RBXScriptConnection`,
and `connection`, but omitted the commonly exposed `LuaConnection` field. V601
examines all four plus `SignalConnection`, and reports the observed type of every
known wrapper field whether or not `Function` is exposed.

## Discovery evidence

For every `UserInputService.InputChanged` connection, the report records:

- wrapper index and origin;
- exact identity result against `controller.inputChangedConn`;
- exposed wrapper fields and their Lua/Roblox types;
- function signature, closure kind, source, name, line, and argument shape;
- constants and upvalues examined;
- direct or nested reference to the active controller;
- score, accepted route, or precise rejection reasons.

It also inventories functions on the active controller, its metatable, and the
camera module. If no safe route installs, a bounded/yielding `getgc(true)` scan
records camera/input-shaped closures as diagnostic candidates only.

`firesignal(UserInputService.InputChanged, ...)` and VirtualInputManager mouse
injection are capability-reported but deliberately not used: the first fans out
to unrelated listeners, and the second is an absolute/global input path that can
change modality. Neither proves isolated access to the Legacy camera stage.

## Activation order

1. Hook a callback `Function` only when exact connection identity or an active
   controller upvalue proves ownership.
2. If `Function` is hidden, accept `wrapper:Fire()` only when the wrapper maps
   exactly through `LuaConnection` (or another identity field) and exposes
   reversible `Disable()` plus `Enable()` isolation.
3. If neither route is proven and reversible, leave V500 untouched.

The wrapper-Fire route disables only the exact Legacy camera connection, relays
the real event to that same callback, then relays the centered synthetic
`MouseMovement`. Cleanup or runtime fallback re-enables the original connection.

## Runtime proof fields

Run this after performing several one-finger camera drags:

```lua
getgenv().PCV601Report()
```

The output is chunked so Delta does not hide the candidate evidence. The summary
separates:

- `callbackFound`: identity/ownership was proved;
- `callbackRouteInstalled`, `callbackHooked`, and
  `callbackWrapperFireActive`: how the callback was reached;
- `callbackExecuted` and `callbackExecutedEvents`: a callback dispatch completed;
- `syntheticAcceptedEvents` / `syntheticRejectedEvents`: proxy dispatch result;
- `rotateInputChangedEvents` / `rotateInputUnchangedEvents`: synchronous, real
  change in the active controller;
- `relayGate`: whether touch preference, camera lock, humanoid state, or another
  prerequisite blocked the synthetic attempt;
- `fallbackReason`: the exact reason V500 is currently handling camera input;
- `validationReady`: true only after a proved callback executed a synthetic event
  and produced an observable `rotateInput` change with `relayedEvents > 0`.

For a short summary without the evidence chunks:

```lua
getgenv().PCV601Report(false)
```

## Non-negotiable invariants

V601 does not call `UpdateMouseBehavior()`, select `CameraRelative`, write
`Camera.CFrame` or `HumanoidRootPart.CFrame`, or change `Humanoid.AutoRotate`.
The V500 and V20 files remain unchanged.

## Interpretation order for the next Delta result

1. If `callbackFound = false`, use the candidate/rejection evidence to extend
   discovery; do not tune movement.
2. If found but `callbackRouteInstalled = false`, inspect hook/Fire/isolation
   capability failures.
3. If installed but `syntheticAttempts = 0`, inspect `relayGate` and
   `lastSyntheticStatus`.
4. If synthetic dispatch is accepted but `rotateInputChangedEvents = 0`, the
   callback ignored that proxy shape or writes a different state field.
5. Only when `validationReady = true` is there evidence that this build actually
   exercised the intended MouseMovement experiment.

