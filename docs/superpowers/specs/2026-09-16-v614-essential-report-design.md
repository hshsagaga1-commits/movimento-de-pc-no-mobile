# V614 Essential Report — Design

## Goal

Replace only the post-collection report construction/export path of V614 so a
mobile user can transport the evidence in a small number of chunks. Collection,
hooks, V604 ownership/relay, ABBA, segment formation, matching, calipers,
bootstrap configuration, gain, sensitivity, and all observed game state remain
unchanged.

The essential report must be sufficient to audit the route-conditioned result
and the temporal/pose causal questions without exporting repeated raw snapshots
that do not participate in the final comparison.

## Current size cause

The current full report emits four high-volume sections:

1. every accepted per-frame scalar sample, including samples outside matched
   segments;
2. every eligible segment, including segments not selected by the matcher;
3. four complete temporal-pose boundary snapshots for every frame in every
   matched segment;
4. repeated constants inside those snapshots: joint C0/C1, joint endpoints,
   animation metadata, FOV, viewport, and identical state.

The third category dominates the roughly 210 transport chunks. Raw telemetry
continues to exist in memory; only its report projection changes.

## Essential data model

The report contains a canonical JSON payload plus short human-readable summary
sections. The JSON schema is versioned and contains only plain values.

### Run and integrity

- version, report ID, probe timing and frame counts;
- full configuration governing standing, segmentation, matching, bootstrap,
  phase targets and route behavior;
- A1/B1/B2/A2 counters, eligible/rejected counts and window completion state;
- callback, controller, correlation, telemetry, UI and evidence-drop counters;
- ownership/relay/fail-open and prohibited-write flags already reported;
- matched-pair count, validation readiness and parity status.

### Constant dictionaries

- unique viewport/FOV combinations;
- unique joint definitions: joint name, Part0, Part1, C0 and C1;
- unique animation-track metadata: AnimationId, name, looped, priority and
  length.

Samples reference dictionary IDs. Constants are not repeated per boundary.

### Matched pairs and segments

Only the one-to-one pairs returned by the unchanged matcher are exported. Each
pair retains:

- Touch/Relay segment IDs and ABBA windows;
- start/end timestamps, duration, frame count, direction, total signed/absolute
  yaw, net/absolute pitch and the original matching gaps/score inputs;
- existing Head, PrimaryPart, subject and returned-CFrame screen metrics;
- start/end Head↔PrimaryPart, Head↔subject and subject↔PrimaryPart geometry;
- compact yaw/pitch trajectories needed to audit segment totals and timing.

### Temporal/pose evidence

For each matched segment, preserve:

- full start and end snapshots at CameraModule-before, first/last
  Controller-before/after, and CameraModule-after boundaries;
- Camera, PrimaryPart and Head CFrames and PrimaryPart-relative Head CFrame;
- variable Neck/Waist/RootJoint Transform values;
- active animation state at start/end: track reference, TimePosition,
  WeightCurrent, WeightTarget, Speed and IsPlaying;
- per-frame compact analytical series containing time, dt, yaw/pitch, boundary
  screen coordinates/depth and the variable deltas actually consumed by the
  temporal/root/joint/animation/projection decomposition.

The compact series must contain every numerical input used by a final metric.
It must not repeat C0/C1 or track metadata.

### Analysis results

- pair-by-pair decomposition for camera-update, inter-frame/root,
  PrimaryPart-relative Head, joint, animation-progress and projection/depth
  terms;
- initial pose/camera gaps and temporal controls;
- aggregate distributions, paired effect estimates and moving-block bootstrap
  CI using the existing configuration;
- every final causal flag and the precise unresolved variable when a conclusion
  remains unproved.

## A/B equivalence contract

At report construction time:

1. **A** analyzes the complete in-memory matched telemetry.
2. The runtime builds and serializes the essential model.
3. The serialized JSON is decoded again.
4. **B** analyzes only that decoded model.
5. A canonical comparator checks all numerical outputs at the report's official
   precision and exact equality for categorical decisions.

The report records mismatches. `validationReady` for the essential export may
not be true unless A and B match. Any input whose removal changes or prevents a
metric must be restored to the essential schema.

## Size accounting and transport

- `fullReportChars`: exact character count of the legacy representation,
  produced by a count-only sink that does not retain the multi-megabyte string;
- `essentialReportChars`: character count of the final essential report;
- `reductionPercent`: reduction relative to the legacy count;
- `essentialChunks`: chunks produced by the existing 30,000-character transport
  envelope.

The chunker, report ID, navigation and exact payload reconstruction checks stay
in place, but their input becomes the frozen essential report.

## Explicitly omitted export categories

The report contains a removal manifest with a reason for each omission:

- unmatched accepted frames: not used by pair metrics or causal controls;
- rejected and unmatched eligible segments: matching diagnostics retain counts
  and reasons, while their pose telemetry is absent from final comparisons;
- repeated C0/C1, Part0/Part1 and track metadata: replaced by dictionaries;
- repeated FOV/viewport: replaced by dictionary references;
- GUI status messages and redundant debug/evidence lines: represented by final
  counters and integrity fields;
- intermediate diagnostics already deterministically summarized by an exported
  final metric: omitted only when A/B equivalence remains exact.

## Test strategy

1. Write a failing source/behavior test requiring an essential report entry
   point and ensuring export no longer calls the legacy full-report builder.
2. Use deterministic synthetic matched telemetry to verify dictionary
   deduplication, matched-only selection and omission manifest.
3. Run A/B analysis through serialize/decode and require identical canonical
   outputs, including an intentional-missing-field negative test.
4. Verify size accounting, reduction arithmetic and chunk reconstruction.
5. Compile runtime and Loader with Luau; diff-audit scientific configuration and
   acquisition/matching regions against commit
   `93e71fdb47baee1aa9f9b2b019cc23609b38d562`.
6. Reconfirm V20, V500 and V604 SHA-256 values and prohibited-write absence.

## Safety and versioning

No V615 is created. No property or input behavior is mutated. Loader continues
to load the same V614 filename with a cache-busted essential-report revision.
The final technical note documents exact omitted categories, equivalence result,
size result, tests, commit and hashes.
