# PC Movement V3.2.3 — normal camera, no Grid Assist, A/D + reverse-hop experiment

Based on the last no-Assist V3.2.2 branch, **NOT** the buggy independent-facing experiment.

### Exact changes
- No independent-facing module, root.CFrame writes or changes to Roblox's natural character AutoRotate.
- Existing camera touch gate remains as it was in the original PC Movement; it only separates joystick touches from camera touches.
- No Grid Assist install, raycasts, contact queries, velocity impulses, gravity alterations, rail magnetization, or hooks into game physics.
- Instant A/D swaps: removed the 16 ms W+A+D sweep that temporarily cancels side movement.
- Opposite A/D key is released BEFORE engaging the other direction.
- A/D side-corridor widened from analog rear/forward |z| <= 0.24 to <=0.33 for more stable side input.
- Reverse diagonal input stays S+A / S+D during jump hold, with mild hysteresis to reduce unwanted S-only drops.
- When holding jump and pressing backward joystick (z>0.22), Space-up and Space-down are delivered on ALTERNATING frames so the game may detect repeat jumps more reliably (up to 30 down pulses per second at 60 FPS; 15 at 30 FPS). Normal forward hopping uses the original jump macro unchanged.
- All original UI, W+A/W+D standing mapping, W+A+D center and crouch/emote A/D sides preserved.

### Limits
**These are input-layer changes only.** They cannot guarantee stronger actual adhesion to a grid/rail or reverse bunnyhopping, both of which depend on Evade's physics and server decisions. The character will still move according to Roblox's camera-relative keyboard control; no deliberate camera-independent facing from previous broken branch.

### How to test
1. REJOIN to ensure no previous facing/controller hooks survive.
2. Run PCMovement_V323_Camera_Normal_AD_Reverso_Loader.lua.
3. Check camera rotates normally, A/D left and right, W+A+D center, jump.
4. On rail test A/D side swaps and compare to no-Assist v3.2.2.
5. On rail hold diagonal S+A or S+D with jump and test reverse bhops.
6. Observe whether keyboard grip actually improves; if not, actual physical assistance would be required.

No on-device test was performed. The base branch and original scripts are unchanged.
