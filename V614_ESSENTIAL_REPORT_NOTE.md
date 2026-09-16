# V614 Essential Report R1

## Scope

This revision changes only final report construction and transport. The V614 acquisition loop, read-only temporal pose telemetry, ABBA order, V604 ownership/relay, segment formation, matcher, calipers, bootstrap configuration, camera behavior, and input gain are unchanged.

The runtime still collects the complete telemetry in memory. After collection, it builds two analyses:

- **A — full telemetry:** reads the original matched `segment.samples` objects.
- **B — essential transport model:** reads a JSON encode/decode round-trip containing only the data serialized into the Essential Report.

The report records both canonical analysis digests and a field-by-field parity result at seven decimal places. `validationReadyEssential` can be true only when the original V614 validation is ready and A/B parity is exact at that precision. A missing required essential value therefore fails the parity gate instead of silently weakening a conclusion.

## Preserved evidence

The Essential Report retains:

- run identity, scientific configuration, standing criteria, A1/B1/B2/A2 window counts, integrity/error counters, and matching results;
- every one-to-one segment pair selected by the unchanged matcher, including timestamps, duration, frame count, yaw/pitch totals and trajectories, caliper gaps, and screen metrics;
- full CameraModule/controller boundary snapshots at the start and finish of each selected segment;
- camera CFrame, FOV/viewport, PrimaryPart CFrame, Head CFrame, and `PrimaryPart:ToObjectSpace(Head.CFrame)` evidence required for projection reconstruction;
- Neck, Waist, and RootJoint transforms, with constant C0/C1 definitions interned once;
- animation-track identity and constant metadata interned once, plus variable start/end/per-frame state needed for progression analysis;
- compact per-frame timing, screen coordinates/depth, camera/root/local-Head/joint motion steps, and animation state for temporal decomposition;
- pair-by-pair decomposition, aggregate distributions, moving-block bootstrap/CI, decision rules, and all final causal flags;
- an omission manifest, A/B parity digests, exact report-size fields, and the chunk count used by the mobile exporter.

The preserved causal interpretation remains deliberately conservative: the
endpoint Head displacement is decomposed as within-update plus inter-frame
motion and retains the arithmetic residual for every matched segment. The prior
V614 audit closed that identity with zero residual, found no evidence of a
missing downstream camera-composition step, and found no corresponding
PrimaryPart/subject separation. Relay nevertheless spans substantially more
time and frames for matched yaw, allowing more Head-to-rig/pose evolution and
more projected cancellation. Duration/frame count, initial pose, and animation
state therefore remain uncontrolled confounders. This revision does not call
Relay a confirmed PC mechanism and keeps `causalMechanismProved`,
`implementationTargetIdentified`, `v615Justified`, and `astra6MaxJustified`
false.

## Categories no longer exported

| Removed from transport | Why it is not needed for an auditable final conclusion |
|---|---|
| Unmatched accepted frames | They are never consumed by the matched-pair decomposition, controls, bootstrap, or decisions. Window/sample counts remain. |
| Rejected-segment samples | Only rejection counts/reasons affect acquisition integrity; rejected pose samples are not analyzed. |
| Unmatched eligible-segment telemetry | The unchanged matcher selects the causal comparison units. Eligible totals, matching coverage, and selected pair identities remain. |
| Repeated full per-frame CFrames | Start/finish boundaries remain in full. Intermediate matrices are replaced by lossless-for-analysis derived translation/rotation step values used by the decomposition. A/B parity verifies equivalence. |
| Repeated joint C0/C1 | They are constant definitions interned once and referenced by ID. Variable joint transforms remain. |
| Repeated animation metadata | Animation ID, name, priority, looped state, and length are interned once. Time, weights, speed, and playing state remain where variable. |
| Repeated FOV/viewport values | Camera configurations are interned once and referenced by ID. |
| GUI status messages | They do not enter acquisition validity, reconstruction, matching, statistics, or decisions. |
| Redundant debug/evidence lines | Their final counters and integrity summaries remain; duplicate prose is not a scientific input. |
| Legacy full textual serialization | Its exact character count is computed with a count-only sink for `fullReportChars`; the multi-megabyte string is not retained or transported. |

## Export behavior

`PCV614EssentialReport()` builds the Essential Report after collection. The compatibility alias `PCV614Report()` now returns that same Essential Report. Chunking still occurs only after the final report string is complete and immutable. Concatenating the original-content payloads reconstructs the Essential Report exactly.

The report prints:

- `fullReportChars`
- `essentialReportChars`
- `reductionPercent`
- `essentialChunks`

No target chunk count is enforced. Evidence required by A/B parity takes priority over size.

## Safety and invariants

- No Camera, Focus, RootPart, PrimaryPart, Head, joint, animation, or physics write was added.
- No sensitivity, gain, input semantics, ownership, relay, matcher, caliper, segment, ABBA, or threshold change was added.
- V20, V500, and V604 remain byte-identical.
- No V615 or camera correction was created.
