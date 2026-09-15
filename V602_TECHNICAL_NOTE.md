# V602 — Inherited Callback Probe

## Why this build exists

The real Delta V601 report ruled out the camera-lock gate: `relayGate = open`,
`cameraLockObserved = true`, and `getIsMouseLocked = true`. It also showed why
connection identity could not be recovered through the wrapper: Delta exposes
`LuaConnection` as a boolean, not as the underlying `RBXScriptConnection`.

V602 therefore changes discovery only. Gain, sensitivity, movement, physics,
jump, crouch, and the V500 fallback remain unchanged.

## Route 1 — recursive inheritance scan

V602 starts at the active Legacy camera controller and recursively follows both:

- `getmetatable(table)` (preferring `getrawmetatable` when available); and
- table-valued `__index` entries.

Tables and functions are identity-deduplicated, the traversal is depth-bounded,
and every level reports its `depth`, `origin`, key count, methods, and dedupe
result. Methods related to `InputChanged`, input, mouse, touch, rotation, camera
input, and Enable/Disable have their signature, constants, upvalues, and nested
functions inspected.

The report separately records:

- raw or upvalue references to `inputChangedConn`;
- functions that are likely to receive a `UserInputObject`;
- identity cross-links between inherited methods and functions reachable from
  the existing `UIS.InputChanged` connection closures; and
- the best heuristic candidate versus a stage that has enough proof to activate.

A strong name or constant score is not proof. An inherited method is hooked only
when it has a connection-graph or `inputChangedConn` link, UserInputObject
evidence, and observable arity compatible with `self + UserInputObject`.

## Route 2 — future Connect capture

Only when route 1 proves no inherited stage, V602 installs a filtered observer
for a future `UserInputService.InputChanged:Connect(callback)` call. It first
tries the signal's `Connect` function and then a filtered `__namecall` observer.
All unrelated calls are forwarded unchanged.

V602 does not force the camera to reconnect. If Roblox/Evade naturally reconnects
the controller later, V602 captures both the callback and the real connection
returned by `Connect`. Ownership is proved only after that returned connection
equals the active controller's newly assigned `inputChangedConn`. Only then may
the existing reversible callback hook route activate.

## Runtime report

After loading and performing several one-finger camera drags, run:

```lua
getgenv().PCV602Report()
```

The new groups are:

- `hierarchy*`: traversal coverage, inherited methods, connection references,
  cross-links, best candidate, and proved stage;
- `connectObserver*`: whether the second route is installed and waiting;
- `futureConnect*`: observed Connect calls, captured callbacks, and exact camera
  ownership proofs;
- the existing callback/synthetic/rotate fields, which still distinguish found,
  executed, accepted/rejected, and a real `rotateInput` change; and
- `fallbackReason`, including the exact observer/install state.

Use `getgenv().PCV602Report(false)` for the summary only. The full report emits
chunked evidence so Delta is less likely to truncate it.

`validationReady` remains false until a proved route is installed, executed,
accepts synthetic MouseMovement, changes `rotateInput`, and increments
`relayedEvents` without falling back.

## Invariants and rollback

V602 does not call `UpdateMouseBehavior()`, write `Camera.CFrame` or
`HumanoidRootPart.CFrame`, change `Humanoid.AutoRotate`, use `firesignal`, inject
mouse input through VirtualInputManager, or trigger a camera reconnection.

V500 remains active whenever discovery is unproved or route installation fails.
`PCMovementV20_STABLE.lua` is unchanged, and `LoaderV20Stable.lua` remains the
stable rollback path.
