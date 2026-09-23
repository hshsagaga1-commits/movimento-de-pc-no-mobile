# V614 Temporal + Initial-Pose Controlled Analysis Design

Date: 2026-09-16

## 1. Scope

This revision remains V614. It adds a secondary, read-only analysis that asks
whether the baseline Touch-versus-V604-relay Head-horizontal difference
survives explicit temporal and initial-pose controls.

It does not change:

- V604 ownership or relay behavior;
- Touch or relay input semantics;
- standing acquisition, 60-degree segment formation, ABBA order, yaw/pitch
  measurement, gain, sensitivity, physics, camera behavior, or baseline
  matcher;
- Camera, Focus, RootPart, PrimaryPart, Head, joint, or animation state;
- V20, V500, or V604;
- the interpretation of the already-published baseline V614 result.

No V615 or Astra promotion is permitted by this revision.

## 2. Official evidence and prechange checkpoint

Official input report:

```text
file = = PC MOVEMENT V614 ESSENTIAL REPORT =.md
SHA-256 = d95e2bec884613b9fb174f84e8ba2b9acafcd7d6156f403b88c18c36b40a27fa
frames = 5327
duration = 89.128 s
eligible segments = 32 Touch + 32 relay
baseline matched pairs = 14
analysis parity = true
```

Prechange publication:

```text
main = 74b0c70214d65229576c7fe11a0d55a1003381b4
runtime SHA-256 = 73bbc11f9f3df3cd31b71f40a0d0515c2bea799a5ab21309b100d9155717da10
Loader SHA-256 = ac3fef6dfd1d3c42f82b7d4877e309daaaea488f21d1f528cfe3b82d2843ddb2
V20 SHA-256 = 634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef
V500 SHA-256 = 5f3b04fccab7e26c322b431162d764a08f17ea29bf566643dd47a4ca6616d096
V604 SHA-256 = 19b80d8241b367808a8b815d3c8ef6668a0c4e53454569b9652e2bbae132a571
```

## 3. Baseline matcher remains authoritative and unchanged

The baseline matcher continues to:

1. form candidates from every eligible Touch × relay segment;
2. require the same yaw direction;
3. require `yawGap <= 5 degrees`;
4. require `netPitchGap <= 1 degree`;
5. require `absPitchGap <= 2 degrees`;
6. sort by the existing normalized yaw/pitch score and stable indices;
7. greedily select one-to-one pairs;
8. sort selected pairs by time.

Baseline pairs, bootstrap, CI, and conclusions remain present under a
`baseline` report section. They are never silently relabeled as temporally or
pose controlled.

## 4. Audit finding that constrains the design

The Essential Report retained complete telemetry only for the 14 baseline
pairs. Among those retained segments:

```text
Touch duration range = 0.0667671–0.2161987 s
relay duration range = 0.2164224–0.7003153 s
Touch frame range = 4–9
relay frame range = 10–32
minimum geometric-compatible cross-pair duration gap = 0.0833303 s
minimum geometric-compatible cross-pair frame-count gap = 4
```

No retained cross-pair passes any of the three predeclared temporal+pose
profiles in section 7. This is insufficient overlap, not disappearance or
persistence of the effect.

The previous pruning policy discarded telemetry for the other 18 eligible
segments per route. A new mobile collection is therefore required. Acquisition
does not change; only post-acquisition selection and retention change.

## 5. Control variables and formulas

All candidate gaps are computed before selection.

### 5.1 Existing geometric controls

```text
yawGap = abs(Touch.totalAbsYaw - relay.totalAbsYaw) degrees
netPitchGap = abs(Touch.netPitch - relay.netPitch) degrees
absPitchGap = abs(Touch.totalAbsPitch - relay.totalAbsPitch) degrees
sameDirection = Touch.totalSignedYaw * relay.totalSignedYaw > 0
```

### 5.2 Temporal controls

```text
durationGap = abs(Touch.duration - relay.duration) seconds
frameCountGap = abs(Touch.frameCount - relay.frameCount) frames
animationAdvanceGap = abs(Touch.animationAdvance - relay.animationAdvance) seconds
```

`animationAdvance` is the segment start-to-finish track progression. For a
looped track that wraps, the track length is added before subtracting, exactly
as in the existing essential analyzer.

### 5.3 Initial local Head pose

For `PrimaryPart:ToObjectSpace(Head.CFrame)`, let the translation be `p` and
the rotation matrix be `R`.

```text
localHeadTranslationGap = norm(pTouch - pRelay) studs
localHeadRotationGapDeg = degrees(acos(clamp((trace(RTouch^T * RRelay)-1)/2,-1,1)))
```

This controls the net Head-to-rig pose. It does not claim which Motor6D or
animation produced that pose.

### 5.4 Initial animation state

The dominant initial track is the active track with the largest
`WeightCurrent`; ties use the stable metadata key. A candidate is fail-closed
unless both routes have:

- the same AnimationId, name, priority, and looped state;
- the same HumanoidState;
- valid initial TimePosition and track length;
- initial speed gap no larger than `0.05`;
- initial weight gap no larger than `0.05`.

For a looped track of length `L`:

```text
d = abs(timeTouch - timeRelay) mod L
animationPhaseGap = min(d, L-d) seconds
animationPhaseFraction = animationPhaseGap / L
```

For a non-looped track:

```text
animationPhaseGap = abs(timeTouch - timeRelay) seconds
```

Missing, ambiguous, or mismatched dominant-track state rejects the candidate
with an explicit reason. It is not treated as zero.

### 5.5 Other captured initial geometry

Let `RCamera` and `RPrimary` be initial camera and PrimaryPart rotations.

```text
cameraToPrimary = RPrimary^T * RCamera
cameraPrimaryRotationGapDeg = angular distance between Touch and relay cameraToPrimary
initialHeadDepthGap = abs(Touch.initialHeadDepth - relay.initialHeadDepth) studs
```

FOV and viewport must match exactly. These variables prevent an initial orbit
or projection difference from being mislabeled as a route effect.

The official collection contains no usable Neck/Waist/RootJoint definitions
(`constants.joints=[]`). The report must state this. The matcher must not claim
joint-level initial-pose control when those values are absent.

## 6. Reproducible pose/time distance

Every caliper remains an individual eligibility gate. Among already-eligible
candidates, selection cost is:

```text
D² = sum((gap_i / caliper_i)²)
D = sqrt(D²)
```

The sum includes yaw, net pitch, absolute pitch, duration, frame count,
animation advance, local-Head translation, local-Head rotation, circular
animation phase, camera-to-Primary rotation, and initial Head depth.

No empirical weights are fitted. Each variable is scaled only by its
predeclared caliper.

For deterministic optimization, each normalized ratio is rounded to the
nearest `1e-6` before the squared terms are summed, and the resulting sum is
converted to an integer cost at `1e12` scale. Stable segment IDs are a
secondary lexicographic key only; they are not added to the scientific cost.

## 7. Predeclared sensitivity profiles

These profiles are fixed before the new collection and are never expanded
automatically.

| Control | Strict | Moderate | Broad |
|---|---:|---:|---:|
| durationGap | 0.034 s | 0.067 s | 0.100 s |
| frameCountGap | 2 | 4 | 6 |
| animationAdvanceGap | 0.034 s | 0.067 s | 0.100 s |
| localHeadTranslationGap | 0.025 stud | 0.050 stud | 0.100 stud |
| localHeadRotationGap | 1.0 degree | 2.5 degrees | 5.0 degrees |
| animationPhaseFraction | 0.05 | 0.10 | 0.20 |
| cameraPrimaryRotationGap | 2.0 degrees | 5.0 degrees | 10.0 degrees |
| initialHeadDepthGap | 0.025 stud | 0.050 stud | 0.100 stud |

All profiles also retain the baseline 5/1/2-degree yaw/pitch calipers, same
direction, track/state identity, speed gap `<=0.05`, and weight gap `<=0.05`.

Rationale:

- 34/67/100 ms approximate 2/4/6 frames at 60 Hz without assuming frames are
  independent;
- animation-advance limits mirror elapsed-time limits because the observed
  dominant track speed is 1;
- phase limits are fixed fractions of the track cycle and remain valid across
  different animation lengths;
- pose/orbit limits form nested, interpretable tolerances rather than a search
  for statistical significance.

## 8. Controlled matching algorithm

For each profile independently:

1. build candidates from all 32+32 eligible segments before telemetry pruning;
2. apply baseline direction/yaw/pitch gates;
3. extract control features using protected read-only data already captured;
4. reject missing or invalid features fail-closed with counted reasons;
5. apply every profile caliper;
6. find a maximum-cardinality one-to-one bipartite matching;
7. among maximum-cardinality solutions, minimize total `D`;
8. resolve equal integer-cost solutions lexicographically by the ordered list
   of stable `(Touch ID, relay ID)` pair keys;
9. sort final pairs chronologically for moving-block bootstrap.

A deterministic min-cost maximum-flow implementation is preferred over the
baseline greedy algorithm because the scientific question needs honest maximum
overlap under fixed gates. This does not modify or replace the baseline
matcher.

## 9. Telemetry retention

At `PARAR`, matching is computed before pruning. The retained telemetry set is
the union of:

- baseline matched segments;
- Strict controlled segments;
- Moderate controlled segments;
- Broad controlled segments.

All other eligible-segment telemetry may be removed after summaries and
rejection counts are frozen. This changes only post-acquisition memory/export,
not acquisition or instrumentation.

The Essential Report deduplicates segments referenced by multiple profiles.

## 10. Analysis per profile

For Baseline, Strict, Moderate, and Broad, report:

- candidate count, matched pairs, Touch/relay segment IDs and ABBA windows;
- distributions of yawGap, netPitchGap, absPitchGap, durationGap,
  frameCountGap, animationAdvanceGap, localHeadTranslationGap,
  localHeadRotationGap, animationPhaseGap/fraction,
  cameraPrimaryRotationGap, initialHeadDepthGap, and `D`;
- Head, PrimaryPart, and subject horizontal distributions by route;
- paired relay-minus-Touch effects;
- chronological moving-block bootstrap estimate and CI95;
- whether each CI excludes zero;
- duration, frame count, animation progression, and initial-pose distributions;
- missing-feature and rejection-reason counts;
- coverage relative to the unchanged requirement of 12 pairs.

The screen-space identity is recomputed for Head, PrimaryPart, and subject:

```text
endpoint displacement
= within Controller/Camera update
+ between-frame relative/pose movement
+ arithmetic residual
```

The report includes per-pair components and maximum absolute residual.

## 11. Decision gate

Each profile is evaluated independently. The Moderate profile is the primary
controlled result; Strict and Broad are sensitivity checks.

```text
if matchedPairs < 12:
    result = insufficient-overlap
    temporalConfoundResolved = unproved: insufficient controlled overlap
    initialPoseConfoundResolved = unproved: insufficient controlled overlap
elif controlled Head CI includes zero:
    result = controlled-effect-not-supported
    temporalConfoundResolved = true: fixed temporal gates passed
    initialPoseConfoundResolved = true: fixed pose/animation gates passed
    causal mechanism remains unproved
elif controlled Head CI excludes zero:
    result = controlled-effect-persists
    temporalConfoundResolved = true: fixed temporal gates passed
    initialPoseConfoundResolved = true: fixed pose/animation gates passed
    locate the first differing decomposition component
    causal mechanism still remains unproved until that component is isolated
```

An interval containing zero is described as “effect not supported under these
controls,” not proof of exact equivalence. No equivalence margin is invented
post hoc.

Case C does not create V615. It only permits a written proposal for the next
minimal causal probe.

`v615Justified`, `astra6MaxJustified`, `implementationTargetIdentified`, and
`pcEquivalenceClaimAllowed` remain false in this revision.

## 12. Emergency-mode clue

The visual report that an earlier “emergency mode” sometimes looked closer to
PC is stored separately as qualitative-only context. It is excluded from
matching, statistics, thresholds, and the current decision.

Only if a controlled divergence persists with at least 12 Moderate pairs may a
later static audit compare emergency versus normal hooks, priorities, routing,
CameraModule/Controller calls, and state. That audit is not part of this
revision.

## 13. Essential export and mobile workflow

The existing one-tap `COPIAR REPORT ESSENCIAL COMPLETO` remains the primary
export route. Chunk export remains fallback only.

The report preserves:

- `fullReportChars`;
- `essentialReportChars`;
- `reductionPercent`;
- `essentialChunks`;
- baseline A/B parity;
- controlled full-versus-essential parity for every profile.

Mobile workflow remains:

```text
Loader -> INICIAR -> A1 -> B1 -> B2 -> A2 -> PARAR
-> COPIAR REPORT ESSENCIAL COMPLETO
```

No console, F9, or command between phases is required.

## 14. Files allowed to change

- `PCMovementV614_ControlledYawPitchMatching.lua`
- `Loader.lua` cache revision
- focused reproducibility tests for controlled matching and report parity
- `V614_TEMPORAL_POSE_CONTROL_NOTE.md`
- this specification and its implementation plan

V20, V500, V604, acquisition thresholds, ownership, relay, gain, and camera
behavior are protected.

## 15. Validation requirements

Before publication:

1. baseline matcher characterization test proves identical baseline pairs;
2. cyclic phase tests cover no-wrap, forward wrap, and exact half-cycle;
3. pose rotation tests cover identity and known rotations;
4. controlled matcher tests prove all gates, maximum cardinality, minimum cost,
   deterministic tie-breaking, and fail-closed missing data;
5. sensitivity profiles are asserted as fixed literals;
6. decomposition tests reproduce zero residual from synthetic exact data;
7. full-versus-essential controlled analyses match at report precision;
8. complete clipboard and chunk fallback tests remain green;
9. Luau runtime and Loader compile;
10. prohibited-write audit passes;
11. V20/V500/V604 hashes remain byte-identical;
12. remote `main` is verified after fast-forward publication.
