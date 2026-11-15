# PC Movement V3.2.2 — Grid/Scroll Experimental

Base: feature/pc-movement-v321-jump-fps-20261114. Unmodified in its original branch.

## Changes
- Standing center W -> W+A+D, and old W+A+D center preserved as W+A+D.
- Standing side mappings W+A, W+D and crouch/emote A, D unchanged.
- Existing A/D sector selection and 16-ms sweep unchanged.
- First Space down sent on touch; while held, one Space up/down pair per rendered frame maximum (capped at 60 presses/s). Under repeated slow frames the cap becomes 30 presses/s. Missed frames are NEVER caught up with bursts.
- No extra task loop or Heartbeat listener; original UI, camera, Assist and cleanup retained.
- Can disable at runtime: getgenv().PCKeyboardTouchBridgeV52.SetJumpMacro(false). Enable again by passing true. This is experimental.

## Limits and performance
- This does NOT synthesize scroll wheel input. It sends Space up/down events through VirtualInputManager. Some executors/games may coalesce, drop or ignore pulses.
- <1ms repeated presses are not meaningful or safe to promise with Roblox frames. No FPS gain or rail-speed improvement is guaranteed.
- The default Assist 'light' observes rails but DOES NOT modify horizontal velocity. The alternate original Assist can affect physics and requires separate testing. We did not change it.
- Static structure checks passed; no Roblox iPhone physical test was performed. Test with other scripts off on a private server.

## Validation
1. Start with the last stable V3.2.1 if anything feels broken.
2. On normal ground, check standing forward: W+A+D; sides: W+A / W+D; crouch sides: A / D.
3. Hold jump 1, 5, and 10 seconds; verify repeated attempts via GetState().bridge.jumpPulses and jumpRepeatAttempts, and that the character responds.
4. Check FPS with and without macro, both away from and against a rail.
5. Disable test macro with the API; return to legacy single Space hold.
6. Report: actual frame rate, whether repeated jumps occur, and whether rail speed behaves differently.
