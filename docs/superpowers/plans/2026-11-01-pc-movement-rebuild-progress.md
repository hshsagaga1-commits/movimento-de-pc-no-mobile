# Execution ledger — plan: docs/superpowers/plans/2026-11-01-pc-movement-rebuild.md

- Base: ce4eb8b. Fresh dedicated clone, clean baseline, no existing movement-specific test runner. Historical V614 audit tests concern a separate camera experiment and will be left intact.
- Ruling: user explicitly authorizes continuous implementation and a new branch, so execute inline without an additional planning approval or worktree prompt. Fresh clone is already isolated.
- Pre-flight: core outputs keys/state consumed by runtime; keyboard route exposes readiness before key ledger dispatch; controls own visuals only; grid produces current contact separately from nearby evidence.
- Ruling: no game-specific physical jump or state API is present in the repository or attachment. Use observable floor/state and explicit game booleans, expose unknowns, and never inject velocity to hide uncertainty.

- Task 1: complete — 15 core behavior cases; missing-source RED observed before implementation; exact-chord, mode, reversal, failed-release and jump tests GREEN.
- Task 2: complete — 13 adapter cases plus control/runtime/mobile suites. Regression failures were reproduced before fixing angle clipping, migration snapshot ordering, late body parts, terminal touches, camera replacement and controller reactivation.
- Review at 086e480: no critical findings; six important lifecycle/controller issues. Fixed terminal-touch reconciliation, both global-disable contracts, startup rollback/callback stop, camera ownership across replacement, hook-chain ownership and knob recovery. Added corresponding regressions.
- Ruling: transient KeyboardEnabled facade applies to the synchronous activation regardless of executor caller identity; restores real values immediately afterward. Offline capability test covers checkcaller=true. Actual Delta semantics remain unvalidated.
- Ruling: retain an inactive hook predecessor when a later hook depends on it; never overwrite another component on Stop.
- Task 3 source/testing: complete — deterministic standalone, six modules, optional remote loader, docs and complete Lua + Luau behavior suite. 112 historical files byte-identical to ce4eb8b. No forbidden physical writers or runtime HTTP dependencies in the standalone.
- Host-only benchmark: 100000 core updates in 0.399 seconds; not an iPhone performance claim.
- Remaining: final reviewed-fix commit publication and remote head/file verification. No merge into an older branch is requested.
- Final fix verification at ab8dc7f: the same reviewer confirmed all six findings and native key replay resolved, with no concrete blocker. Independently reran Lua/Luau suite and compilation. Live device limits retained.
- Publication ruling: ordinary Git push has no write credential in this checkout. Use the authorized connected GitHub Git-data API to publish the reviewed source tree in the new branch; never update the reference branch.
- Task 3: complete — published feature/pc-movement-rebuild-20261101 through GitHub; source commit 579cdaec8719651534ce243451869b084c481563. Remote source tree c608050be7fe83c73edebc056e85db0e3eb3e7b5 equals local git write-tree.
- Remote delivery verified: standalone blob cbf680fd78a19ef55ae877711d9a2c250fe111cb (62072 bytes); loader blob 23519fdf7800e92433fc1867b43ecbf8a1f5157d. Loader content fetched from new branch and matches local.
- Reference branch remains ce4eb8b6deb47e0690301bd38f1b78eb0e19dcaa. No merge or overwrite of earlier versions.
- Completion boundary: implementation, offline Lua/Luau tests, review and publication complete. Live Evade/Delta physics, game state signals, exact micro-hop and iPhone performance remain pending on-device testing.
