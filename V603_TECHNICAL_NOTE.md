# V603 — Dynamic Inherited Stage Proof

## Result that triggered this build

The Delta V602 evidence exposed the BaseCamera stage directly:

- `ConnectInputEvents` contains `InputChanged` and `inputChangedConn`;
- `OnInputChanged` branches from real `Touch` to `OnTouchChanged` and from
  `MouseMovement` to `OnMouseMoved`;
- all three methods exist in the inherited BaseCamera table; and
- the controller is already mouse-locked while the relay gate is open.

V603 therefore does not use `getconnections()` wrapper identity as its primary
route. It dynamically proves the inherited method itself.

## Phase 1 — observational pass-through

V603 recursively locates the exact inherited `OnInputChanged`, `OnTouchChanged`,
and `OnMouseMoved` methods. It hooks `OnInputChanged` and always calls the
original with the original `self`, `input`, `processed`, and trailing arguments.
No input is replaced in this phase.

Optional pass-through hooks on `OnTouchChanged` and `OnMouseMoved` show which
branch the original `OnInputChanged` actually calls. They do not alter arguments
or return values.

An execution contributes to the dynamic proof only when `self` is exactly the
active camera controller at call time. A real Touch under that condition sets:

```text
dynamicStageProven = true
validationReady = true
```

The report includes the requested fields:

- `onInputChangedObserved`;
- `onInputChangedActiveControllerHits`;
- `realTouchHits`;
- `onTouchChangedHits`;
- `onMouseMovedHits`;
- `rotateBefore` / `rotateAfter`;
- `lastInputDelta`;
- `dynamicStageProven`; and
- `validationReady`.

It also distinguishes total helper hits from helper calls correlated to the
current `OnInputChanged` invocation.

Run after several normal one-finger camera drags:

```lua
getgenv().PCV603Report()
```

## Phase 2 — explicit same-object experiment

Phase 2 is forced off every time V603 loads. It cannot be enabled until phase 1
has dynamically proved a real Touch on the active controller.

After obtaining and saving the phase-1 report, enable it explicitly in the same
session:

```lua
getgenv().PCV603SetPhase2Enabled(true)
```

For an eligible unprocessed real Touch with non-zero delta, phase 2 calls the
inherited `OnMouseMoved` with the exact same UserInputObject. It does not create
a MouseMovement proxy and does not change the object's type, delta, position, or
other fields. That event replaces the normal `OnTouchChanged` branch only while
the manually enabled experiment is active.

The phase-2 report records attempts, errors, synchronous `rotateInput` changes,
and whether the `OnMouseMoved` observer saw the same object identity. Disable it
at any time with:

```lua
getgenv().PCV603SetPhase2Enabled(false)
```

An `OnMouseMoved` error immediately disables phase 2 and forwards that same
event to the original `OnInputChanged`, restoring V500 behavior. Repeated calls
without an observable `rotateInput` change also auto-disable the experiment.

## Invariants

V603 does not reconnect `UIS.InputChanged`, use `firesignal`, inject mouse input
through VirtualInputManager, call `UpdateMouseBehavior`, write Camera or RootPart
CFrame, alter AutoRotate, or change gain, sensitivity, movement, or physics.

V500 remains loaded underneath as the observational and fail-open path.
`PCMovementV20_STABLE.lua` and `LoaderV20Stable.lua` remain unchanged.
