# PC movement rebuild

User supplied the implementation scope and explicitly requested continuous execution through delivery. This is the design chosen by the implementer; no further approval gate is needed.

## Goal and constraints

Preserve the V3/V6 joystick and PCJump visual objects, assets, layout, resizing and external layout attributes. Replace every movement writer with one input engine. Standing ground permits W+A, W, W+D and S; crouch, airborne BHOP/reverse movement, moving emotes and actual grid contact use A/D without injected W. No speed, impulse, CFrame, collision or humanoid movement-property writes are permitted. Native crouch is untouched. Keep mobile camera input distinct from captured control fingers.

## Evidence and alternatives

The current reference is ce4eb8b. Its loader calls PCModeLockV3, fetching an older branch bridge and a nested V5 bootstrap chain. Bridge V6/V3 has staged W+A+D transitions; near-forward joystick jitter also produces W+A+D. V3.1 projects and overwrites horizontal velocity, adds inward adhesion and directly writes Y for two hops. Held reversal interpolation can remove 70% of speed. These explain script-created resistance but do not prove the game's own physics.

Patching that stack retains competing writers and network-dependent bootstraps. Replacing physics with a custom velocity motor contradicts the request. Chosen: one keyboard input owner, an independent physical observer and passive grid detector, with only buffered native Space requests as contact assistance. Reuse presentation, not the old movement loop.

## Architecture and interfaces

- `rebuild/Core.lua`: pure observations -> layered state flags -> immediate digital chords; key ledger with transport-failure retention, native-jump scheduling and a bounded optional diagnostic ring.
- `rebuild/KeyboardRoute.lua`: select/enable the real PlayerModule Keyboard controller. Preserve the known temporary mobile capability bootstrap, release the facade outside activation, never force globally disabled controls.
- `rebuild/Controls.lua`: reuse or recreate the original named GUI, identical native sprites and small/large screen formulas. Captured InputObjects own their full lifetime; knob interpolation affects visuals only.
- `rebuild/GridSensor.lua`: bounded broad query plus actual collidable body contacts. Names/tags and repeated bars are evidence levels, not an official Evade API. Only real current confirmed contact may qualify for a buffered native jump; proximity is diagnostic. No force/adhesion code.
- `rebuild/CameraGate.lua`: suppress the captured control InputObjects through camera replacement, retaining their full lifetime and leaving unrelated camera fingers alone.
- `rebuild/Runtime.lua`: lifecycle, physical/state observations, camera touch gate, input events, performance budget, compatibility globals and diagnostics. No historical bootstrap is executed.
- `PC_Movement_Rebuild_AUTOEXECUTE.lua`: deterministic self-contained generated bundle; one file for AutoExecute, with no runtime HTTP dependencies.
- `PCMovementRebuildLoader.lua`: optional single remote entry point, pinned to the new reconstruction branch.

## State policy

FloorMaterial and Humanoid state establish grounded/airborne, not animations. All airborne movement uses lateral A/D; this protects reverse BHOP even with standing animation. Normal standing ground uses the four specified chords. Crouch/emote read explicit booleans/attributes, plus the historical ControlsGui/PCFrame/Stand visibility convention for crouch. Unknown game-specific state is reported; providers/exact emote animation IDs may supply evidence without guessed speed/animation heuristics. Reverse is velocity relative to flattened camera forward. Overlapping flags survive contact/flight changes. An intentional jump can preserve the airborne lateral policy for a short landing buffer, never indefinitely.

## Grids and jump

Broader spatial discovery never creates colliders or changes part properties. Ordinary floor/walls, noncollidable decoration, other characters and distant/cached contact cannot trigger assistance. Truss/climbable state is recorded separately. The contact jump is a native Space request, requires current contact, user jump intent, a grounded alive character and cooldown/rearm. It does not create an air jump. A normal native jump cannot promise the video micro-hop height. The game may reject it; that is logged rather than overridden.

## Video evidence

The attachment is 17.367 s, 896x512, 30 fps. Gameplay runs approximately 0–14.3 s in three edited scenes: exterior upper walkway/rails (~0–3.9), outdoor walkway/borders (~4–8.8), interior elevated rails (~8.9–14.3). Repeated lateral arcs, brief approach/departure and airborne stretches are visible. Keyboard keys, contact normals, crouch/emote state and vertical impulse source are absent. Camera rotation and cuts rule out deriving world acceleration or proving a special contact jump from image displacement. Detailed annotated observations are delivered with the implementation.

## Validation boundary

Execute deterministic tests of production core and adapters, syntax-compile the bundle and modules with Luau when available, check no forbidden physics writes and no runtime dependency chain. Test lifecycle, failed input transport, camera ownership, neutral/reverse state changes, jump rearm, contact identity and query ceilings. Live Roblox/Delta/iPhone physics, actual map naming and emote signals require on-device tests and are not claimed validated.
