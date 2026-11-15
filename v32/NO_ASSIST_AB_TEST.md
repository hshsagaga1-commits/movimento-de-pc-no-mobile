# PC Movement V3.2.2: no-Assist A/B test

This is the PC Movement V3.2.2 grid-scroll experimental branch with **only the Grid Assist runtime disabled**.

- Preserved: W+A, W+D, W+A+D center; crouch/emote A/D; adaptive jump macro; UI; camera; keyboard bridge; sector choices; jump mappings.
- Removed from runtime: Grid Assist startup and its raycast/overlap/contact/heartbeat/facing logic. The original assist definitions remain embedded in the bundle, but are never invoked. SetAssistMode() intentionally refuses to re-enable Assist.
- Original source branch remains intact: `feature/pc-movement-v322-grid-scroll-20261115`.
- A running older PCMovementV32 cannot silently masquerade as no-Assist: this version asks you to rejoin.

## Comparison
1. Rejoin Evade. Run this version alone, ideally private server, same map/rail.
2. Check GetState().assistMode == "disabled" and GetState().assist == nil.
3. Record how fast you gain speed at the rail, how long speed persists, how many jumps and average FPS.
4. Rejoin and test original V3.2.2 under same conditions. Avoid running two PC Movement versions in one session.
5. No guarantee of improved rail speed: original V3.2.2 'light' Assist monitored contact and visual facing but did not write horizontal velocity.

Only static checks were done. Physical Roblox/iPhone validation is pending.
