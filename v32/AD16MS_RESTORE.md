# V3.2.3 — original 16ms side transition restored

Based on V3.2.3 normal camera / no Grid Assist. Corrects an unnecessary removal of V3.1's timed A/D transition.

- **Original 16ms transitional chord is restored verbatim**, including the forward-only condition z < -0.24, SIDE mapping, and conditional W+A+D / A+D intermediary. This prevents immediate transitions in the cases covered by the original logic.
- **Original V3.1 key press/release order restored verbatim**: added keys go down before removed keys go up.
- Camera and Roblox character rotation unchanged from original no-Assist variant; buggy independent-facing module NOT included.
- Grid Assist remains off.
- Preserves V3.2.3 reverse-bhop input experiment and A/D side analog stability outside the restored transition; these are untested on device and might still need adjustment.
- No speed/rail-adhesion guarantee; this version only changes input timing. No iPhone test carried out.

Rejoin the game before trying this build; ensure old script hooks are gone.
