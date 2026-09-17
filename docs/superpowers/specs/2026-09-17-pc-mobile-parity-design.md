# PC Mobile Parity Design

## Goal
Reproduce the relevant Evade PC control/camera behavior on mobile while keeping the real mobile HUD identity and avoiding unrelated cross-loading between features.

## Scope
Four isolated subsystems:
1. Joystick digital sector mapping.
2. Body/camera presentation for Overhaul and Legacy.
3. Camera sensitivity + optional directional precision (implemented in the separate `EvadeCameraSpeedControl` repository).
4. Legacy grid-contact diagnostics and a conservative surface-normal assist that preserves native game acceleration instead of injecting speed.

## Global Constraints
- Keep Overhaul HUD/mobile touch identity visible; never re-enable global PC spoof after bootstrap.
- Keep existing 200 ms jump burst unchanged.
- Keep native crouch behavior unchanged.
- Keep movement digital/full-strength; joystick position chooses key chords, not analog speed.
- Camera precision must have zero temporal carry/inertia.
- Sensitivity range is 0.1x to 2.0x in 0.1x steps, default 1.0x.
- Precision toggle is independent of sensitivity.
- Feature loaders must be independent: running camera sensitivity must not initialize joystick or body-view modules, and vice versa.
- Do not inject arbitrary velocity for grid movement. Prefer reproducing contact geometry/input conditions that let Legacy generate its native acceleration.
- Runtime correctness inside Evade/Delta remains a manual gate; static/model tests may not be represented as in-game validation.

## Joystick Mapping
Target upper half distribution is approximately:
- W pure: narrow central 20% band.
- A/D pure: roughly 50% combined lateral ownership.
- WA/WD: remaining transition area.

The mapping remains spatial and digital. The existing A<->D dry lateral transition behavior is preserved unless it conflicts with direct access to WA/WD, in which case the latch is restricted to a small side-arc hysteresis rather than the whole upper arc.

## Overhaul Body View
The current implementation is wrong because it moves the camera backward along LookVector, which can make the effective viewpoint feel above/behind the head. Replace that with a first-person presentation that:
- keeps the first-person camera location controlled by Roblox/Evade;
- forces lower-body parts visible locally;
- applies at most a small vertical subject/camera presentation offset, not backward zoom;
- aims for the maximum leg/body visibility demonstrated by the PC reference while staying in first person.

## Legacy Camera
Remove bounding-box fit zoom. Use a smooth pitch-to-distance correction measured relative to the game's native third-person distance. The curve must:
- stay closer than the old 6.8-9.2 stud fit behavior;
- vary continuously with pitch;
- move farther only in the mid/downward range where the PC reference shows more body;
- reduce again at extreme downward pitch;
- preserve collision behavior and never force first person outward.

## Camera Precision
In `EvadeCameraSpeedControl`, keep the 0.1-2.0 slider and add an independent Precision toggle. Precision performs memoryless axis cleanup:
- near-horizontal gestures suppress small vertical contamination;
- near-vertical gestures suppress small horizontal contamination;
- genuine diagonals remain diagonals;
- large/fast swipes retain their magnitude and speed;
- no smoothing state, velocity carry, or post-release motion.

The UI must expose the current multiplier and Precision ON/OFF without loading any movement script.

## Legacy Grid Contact
First deliver a diagnostic module that records, while near a candidate grid/surface:
- commanded digital chord;
- Humanoid.MoveDirection;
- root AssemblyLinearVelocity;
- camera look/right vectors;
- raycast hit normal and contact distance;
- crouch/stand state when discoverable;
- whether speed is increasing while contact is maintained.

Then implement a conservative assist only when a nearby surface contact is verified. Decompose commanded movement into surface-normal and tangent components. Preserve native tangent movement and only restore a small inward normal component when touch/control geometry would otherwise lose contact. The assist must disengage immediately when the user commands away from the surface or no valid contact exists. No direct speed boost is allowed.

## Isolation / Loaders
Movement repository exposes separate standalone loaders for:
- joystick only;
- body view only;
- grid diagnostics/assist only;
- optional combined test loader.

`EvadeCameraSpeedControl` exposes only camera sensitivity/precision and never imports the movement repository.

## Verification
Each mathematical behavior gets model tests with red-green evidence before code changes. Source contract checks verify loader independence and protected behaviors. In-game claims require user runtime testing in Legacy/Overhaul.
