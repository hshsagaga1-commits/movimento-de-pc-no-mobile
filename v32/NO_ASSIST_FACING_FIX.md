# PC Movement V3.2.2 — camera-independent facing fix (no Grid Assist)

This branch corrects a regression in the previous no-Assist variant:
removing the light Grid Assist also removed its visual-facing controller.

### Preserved
- Every standing and crouched WASD mapping from v3.2.2 (including W+A+D center)
- Scroll-like adaptive jump macro and FPS safeguards
- Camera routing, UI, keyboard input bridge, posture detection, cursor control
- Grid Assist remains completely inactive (no raycasts, overlap probes, velocity writes, wall magnet or grid-hop)

### Corrected
- New standalone facing-only module (v32/Facing.lua)
- Camera orientation is sampled ONCE at joystick touch start; turning the camera later does not recalculate avatar heading
- Joystick full right points avatar fully right of sampled heading (rather than the W+D 45-degree diagonal)
- AutoRotate is temporarily disabled during the touch and restored afterward or on stop
- Does not write to humanoid velocity, WalkSpeed, camera, or input chords
- No extra contact scans or Heartbeat loops
- GetState().facing provides status, GetState().assistMode remains disabled
- Use getgenv().PCMovementV32.SetIndependentFacing(false) to disable just the facing controller

### Important
This fixes visual *facing* only. Actual keyboard movement direction may still be camera-relative because the underlying Roblox PC controller transforms its own WASD input each frame. A separate controlled test is necessary before changing physics/movement commands. Do not misrepresent this as a confirmed full decoupling of trajectory.

### Test
1. Rejoin Evade and execute only this build.
2. Hold joystick fully right. Turn camera 180° without changing the joystick.
3. Check avatar orientation stays right relative to the original heading.
4. Repeat on a rail; compare movement and FPS with previous build.
5. If anything goes wrong, stop via getgenv().PCMovementV32.Stop() and rejoin; older branch untouched.
No iPhone physical test has been performed.
