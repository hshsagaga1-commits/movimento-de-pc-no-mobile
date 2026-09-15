# V604 — Multitouch Ownership Probe

## What V603 proved

The real Delta V603 run completed 1,133 same-object calls through
`BaseCamera.OnMouseMoved`, with no callback errors and 1,127 synchronous
`rotateInput` changes. The camera route is therefore proved:

```text
real Touch -> active BaseCamera.OnInputChanged -> OnMouseMoved
```

No synthetic UserInputObject is required. V603 also exposed the next defect:
routing every eligible Touch to `OnMouseMoved` lets the DynamicThumbstick finger
rotate the camera and breaks normal joystick + camera multitouch.

## Ownership evidence used by V604

The V603 BaseCamera constants match its runtime state:

- `OnTouchChanged` reads `fingerTouches[input]`,
  `isDynamicThumbstickEnabled`, and `numUnsunkTouches`;
- the active DynamicThumbstick-compatible movement controller keeps its captured
  UserInputObject in `moveTouchObject`; and
- `processed` alone is not ownership. The V603 evidence contains
  `processed=false` Touch changes that produce no camera rotation.

V604 therefore never uses screen halves or `processed=false` as its gate. It
tracks each UserInputObject identity from `TouchStarted` through `TouchEnded` and
uses two independent proofs:

```text
joystick: active movement controller moveTouchObject == input
camera:   active BaseCamera fingerTouches[input] == false
```

Any unknown or conflicting identity stays on the original V500 Touch path.

## Diagnostic mode is the default

The real-Touch Mouse relay is forced off every time V604 loads. First perform:

1. a joystick-only movement;
2. a camera-only drag;
3. hold/move the joystick while dragging the camera with another finger; and
4. a normal two-finger pinch zoom.

Then run:

```lua
getgenv().PCV604Report()
```

The ownership gate becomes proved only after a joystick identity and a camera
identity overlap in time without any role conflict:

```text
joystickTouchesIdentified > 0
cameraTouchesIdentified > 0
simultaneousJoystickCameraObserved > 0
touchRoleConflicts = 0
ownershipGateProven = true
validationReady = true
relayEnabled = false
```

`touchProofSummary` and the active Touch ID fields show the lifecycle of T1, T2,
and later touches, including movement matches, camera-map matches, blocked Mouse
events, relays, and conflicts.

## Manually gated relay

Only after saving a diagnostic report with `ownershipGateProven = true`, enable:

```lua
getgenv().PCV604SetRelayEnabled(true)
```

For each proved single camera Touch, V604 performs exactly two steps:

1. call the original `OnInputChanged` with the original arguments while only
   `panEnabled` is temporarily false; this lets `OnTouchChanged` maintain
   `fingerTouches`, `lastPos`, and pinch bookkeeping without applying Touch pan;
2. call `OnMouseMoved` with the exact same real Touch UserInputObject.

Joystick, unknown, conflicting, and two-camera-finger pinch events never reach
`OnMouseMoved`; they are forwarded unchanged to V500. This avoids double
rotation while keeping camera drag available across the full screen.

The relay result is ready for evaluation only when the report shows:

```text
joystickTouchesBlockedFromMouse > 0
cameraTouchesRelayedToMouse > 0
simultaneousJoystickCameraRelayed > 0
relaySameInputConfirmed > 0
relayRotateChanged > 0
joystickMouseCrossovers = 0
callbackErrors = 0
relayValidationReady = true
```

Disable immediately with:

```lua
getgenv().PCV604SetRelayEnabled(false)
```

## Safety and invariants

V604 fails open on unknown ownership, role conflict, callback error, missing
`panEnabled`, unsupported pinch state, or repeated lack of an observable
`rotateInput` change. It does not reconnect the camera input signal.

V604 does not use `firesignal`, VirtualInput mouse injection, a synthetic
UserInputObject, half-screen classification, `UpdateMouseBehavior`, Camera or
RootPart CFrame writes, AutoRotate changes, gain changes, or physics changes.

V500 remains underneath as the fallback. `PCMovementV20_STABLE.lua` remains
byte-identical with SHA-256:

```text
634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef
```
