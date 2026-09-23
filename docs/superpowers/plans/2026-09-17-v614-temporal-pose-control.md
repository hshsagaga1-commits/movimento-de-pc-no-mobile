# V614 Temporal + Initial-Pose Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic secondary V614 analysis that controls duration, frame count, animation progression, initial Head-to-rig pose, animation phase, and initial camera geometry without changing baseline acquisition or matching.

**Architecture:** Keep the acquisition path and `SEGCFG.matchSegments()` byte-identical, freeze all 32+32 eligible segments before pruning, and derive compact control features from already-captured read-only telemetry. Run independent Strict, Moderate, and Broad maximum-cardinality/minimum-cost matchers, retain the union of their telemetry with the baseline set, and export baseline and controlled results as distinct Essential Report sections with fail-closed decisions.

**Tech Stack:** Luau/Roblox runtime, Python 3 source-contract test runners, standalone Luau CLI, Git, SHA-256 invariants.

**Spec:** `docs/superpowers/specs/2026-09-16-v614-temporal-pose-control-design.md` at checkpoint `a288b72c0ed8a7154045be9d797be677c1bd4d3d`

## Global Constraints

- V604 ownership, relay behavior, same-Touch `UserInputObject`, and V500 fail-open remain unchanged.
- `standingObservation`, `recordPairedSample`, 60-degree non-overlapping segment formation, ABBA order, phase targets, yaw/pitch measurement, and `SEGCFG.matchSegments()` remain unchanged.
- Baseline calipers remain exactly `yaw <= 5 degrees`, `net pitch <= 1 degree`, and `absolute pitch <= 2 degrees` with same-direction gating.
- Strict, Moderate, and Broad control profiles are fixed literals from the approved specification and never expand in response to observed coverage or significance.
- V20 SHA-256 remains `634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef`.
- V500 SHA-256 remains `5f3b04fccab7e26c322b431162d764a08f17ea29bf566643dd47a4ca6616d096`.
- V604 SHA-256 remains `19b80d8241b367808a8b815d3c8ef6668a0c4e53454569b9652e2bbae132a571`.
- No Camera/Focus/RootPart/PrimaryPart/Head/joint/animation write, input synthesis, gain change, sensitivity change, physics change, V615 creation, Astra promotion, or PC-equivalence claim is allowed.
- The one-tap `COPIAR REPORT ESSENCIAL COMPLETO` route remains primary; chunk export remains fallback.
- A controlled profile with fewer than 12 pairs is `unproved: insufficient controlled overlap` and can never justify a mechanism, implementation target, V615, or Astra.

## File Structure

- Modify `PCMovementV614_ControlledYawPitchMatching.lua`: add pure control-feature math, fixed profiles, controlled candidate construction, deterministic optimal matching, pre-prune result freezing, telemetry-union retention, profile analyses, parity, report sections, and fail-closed decisions.
- Modify `V614_ESSENTIAL_REPORT_TEST.py`: update the synthetic Essential schema to R2 and prove full-versus-essential equality for baseline plus all controlled profiles.
- Modify `V614_REPORT_CHUNK_EXPORT_TEST.py`: update only the Loader revision expectation and re-prove complete clipboard plus lossless chunk fallback.
- Create `V614_TEMPORAL_POSE_CONTROL_TEST.py`: characterize the protected baseline/acquisition slices and execute pure Luau tests for profiles, cyclic phase, feature gates, cardinality, cost, deterministic ties, retention union, and decision safety.
- Create `V614_TEMPORAL_POSE_CONTROL_NOTE.md`: document formulas, fixed calipers, report interpretation, missing joint-definition limitation, mobile workflow, and hashes.
- Modify `Loader.lua`: cache-bust the same V614 runtime filename after all scientific and invariant tests pass.

---

### Task 1: Lock Baseline and Acquisition Invariants

**Files:**
- Create: `V614_TEMPORAL_POSE_CONTROL_TEST.py`
- Read-only reference: `PCMovementV614_ControlledYawPitchMatching.lua:890-1195, 1538-1572, 2175-2214`
- Read-only reference: `PCMovementV20_STABLE.lua`
- Read-only reference: `PCMovementV500_ScrapFusion.lua`
- Read-only reference: `PCMovementV604_MultitouchOwnershipProbe.lua`

**Interfaces:**
- Consumes: checkpoint `a288b72c0ed8a7154045be9d797be677c1bd4d3d` and current source text.
- Produces: a test runner that fails if protected source slices, baseline behavior, or protected hashes change.

- [ ] **Step 1: Add exact protected-slice extraction and expected digests**

Create a Python runner that extracts text between stable anchors and asserts these checkpoint digests:

```python
PROTECTED_SECTIONS = {
    "standingObservation": (
        "local function standingObservation(frame)",
        "\nlocal function routeMatchesPhase",
        "3fb21fc9df1e874d3236554ffcda9de185bbaee489904d1955f871c2c1ce821d",
    ),
    "recordPairedSample": (
        "local function recordPairedSample(",
        "\nfunction SEGCFG.segmentScreenMetric",
        "2f790200d79140c884d634f65828c9bc51feab50717c5824aed7aa180e40c952",
    ),
    "closeCurrentSegment": (
        "function SEGCFG.closeCurrentSegment(reason)",
        "\nfunction SEGCFG.startSegment",
        "4a5c00d066a4d763c1e7763314fe9e796909ee945b027be2c8ba444924cd6ca8",
    ),
    "segmentConsumer": (
        "segmentConsumer=function(sample)",
        "\nlocal function finalizeFrame",
        "c13a1ce2ca5f6cad32ff3c82855a9f2348bdd0a046b4866673b7829f5e694203",
    ),
    "matchSegments": (
        "function SEGCFG.matchSegments()",
        "\nfunction SEGCFG.telemetryCoverage",
        "d720b294563ff5b550548a9fb6690d33e517693cced879c7f4dcc89faa9cef27",
    ),
    "updateCoverageState": (
        "function SEGCFG.updateCoverageState(segment)",
        "\nfunction SEGCFG.pairMetricArrays",
        "9fe57eebb16f98b60f31de7c8ea37dc9ee7b6806945fa4684a4ff13c512e86f3",
    ),
}
PROTECTED_FILES = {
    "PCMovementV20_STABLE.lua": "634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef",
    "PCMovementV500_ScrapFusion.lua": "5f3b04fccab7e26c322b431162d764a08f17ea29bf566643dd47a4ca6616d096",
    "PCMovementV604_MultitouchOwnershipProbe.lua": "19b80d8241b367808a8b815d3c8ef6668a0c4e53454569b9652e2bbae132a571",
}
```

Also assert literal standing/acquisition constants and ABBA order:

```python
for literal in (
    "local STABILIZE_SECONDS=1.50",
    "local STABLE_CONSECUTIVE_FRAMES=12",
    "targetYaw=60,maxYaw=120,minFrames=3,maxFrameGap=3,maxDuration=1.25",
    'sequence={"A1","B1","B2","A2"}',
    'route={A1="touch",A2="touch",B1="relay",B2="relay"}',
):
    assert literal in source, literal
```

- [ ] **Step 2: Add a behavioral characterization for the unchanged greedy baseline matcher**

Extract the production `SEGCFG.matchSegments()` body into a standalone Luau fixture. Use candidates where greedy score order is observable and assert exact IDs, order, and gaps:

```lua
segmentStats={
  touch={eligible={
    {id="touch-1",totalAbsYaw=60,totalSignedYaw=60,netPitch=0,totalAbsPitch=1,endTime=1},
    {id="touch-2",totalAbsYaw=64,totalSignedYaw=64,netPitch=0,totalAbsPitch=1,endTime=4},
  }},
  relay={eligible={
    {id="relay-1",totalAbsYaw=60.1,totalSignedYaw=60.1,netPitch=0,totalAbsPitch=1,endTime=2},
    {id="relay-2",totalAbsYaw=63.8,totalSignedYaw=63.8,netPitch=0,totalAbsPitch=1,endTime=3},
  }},
}
local pairs=SEGCFG.matchSegments()
expect(#pairs==2,"baseline pair count")
expect(pairs[1].touch.id=="touch-1" and pairs[1].relay.id=="relay-1","baseline first pair")
expect(pairs[2].touch.id=="touch-2" and pairs[2].relay.id=="relay-2","baseline second pair")
```

- [ ] **Step 3: Run the invariant test before feature work**

Run:

```bash
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --baseline-only
```

Expected:

```text
PASS: V614 protected baseline/acquisition source is unchanged
PASS: V614 baseline greedy matcher characterization is unchanged
PASS: V20/V500/V604 hashes are byte-identical
```

- [ ] **Step 4: Commit the guard rails**

```bash
git add V614_TEMPORAL_POSE_CONTROL_TEST.py
git commit -m "Test V614 baseline temporal pose invariants"
```

### Task 2: Add Pure Temporal and Initial-Pose Feature Math

**Files:**
- Modify: `PCMovementV614_ControlledYawPitchMatching.lua:3194-4000` (`V614 ESSENTIAL REPORT PURE HELPERS`)
- Modify: `V614_TEMPORAL_POSE_CONTROL_TEST.py`

**Interfaces:**
- Consumes: plain numeric CFrame arrays, raw or essential animation snapshots, segment boundary analyses.
- Produces:
  - `SEGCFG.controlledProfiles() -> table`
  - `SEGCFG.controlledCircularPhaseGap(a, b, length, looped) -> number?`
  - `SEGCFG.controlledAnimationAdvance(startTime, endTime, length, looped) -> number?`
  - `SEGCFG.controlledDominantTrack(animation, model) -> table?, string?`
  - `SEGCFG.controlledRelativeRotation(primaryCF, cameraCF) -> table?`
  - `SEGCFG.controlledRotationGapDeg(a, b) -> number?`
  - `SEGCFG.controlledInitialHeadDepth(cameraCF, headCF, cameraConfig) -> number?`
  - `SEGCFG.controlledFeatureFromRawSegment(segment) -> table?, string?`

- [ ] **Step 1: Add failing profile-literal and cyclic-animation tests**

Append Luau assertions to the new runner:

```lua
local profiles=SEGCFG.controlledProfiles()
expect(profiles.Strict.durationGap==0.034 and profiles.Strict.frameCountGap==2,"Strict literals")
expect(profiles.Moderate.durationGap==0.067 and profiles.Moderate.frameCountGap==4,"Moderate literals")
expect(profiles.Broad.durationGap==0.100 and profiles.Broad.frameCountGap==6,"Broad literals")
expect(SEGCFG.controlledCircularPhaseGap(1.95,0.05,2,true)==0.1,"cyclic phase wrap")
expect(SEGCFG.controlledCircularPhaseGap(0.25,1.25,2,true)==1,"half-cycle distance")
expect(SEGCFG.controlledCircularPhaseGap(1.95,0.05,2,false)==1.9,"non-looped linear phase")
expect(SEGCFG.controlledAnimationAdvance(1.95,0.05,2,true)==0.1,"animation advance wrap")
```

- [ ] **Step 2: Run the feature test and verify the red state**

Run:

```bash
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --features
```

Expected: FAIL because `SEGCFG.controlledProfiles` and cyclic helpers do not exist.

- [ ] **Step 3: Implement fixed profiles and cyclic helpers**

Add fresh-table profile construction so callers cannot mutate shared thresholds:

```lua
function SEGCFG.controlledProfiles()
    local shared={yawGap=5,netPitchGap=1,absPitchGap=2,speedGap=0.05,weightGap=0.05}
    local function profile(duration,frames,advance,translation,rotation,phase,cameraRotation,depth)
        return {
            yawGap=shared.yawGap,netPitchGap=shared.netPitchGap,absPitchGap=shared.absPitchGap,
            speedGap=shared.speedGap,weightGap=shared.weightGap,
            durationGap=duration,frameCountGap=frames,animationAdvanceGap=advance,
            localHeadTranslationGap=translation,localHeadRotationGap=rotation,
            animationPhaseFraction=phase,cameraPrimaryRotationGap=cameraRotation,
            initialHeadDepthGap=depth,
        }
    end
    return {
        Strict=profile(0.034,2,0.034,0.025,1.0,0.05,2.0,0.025),
        Moderate=profile(0.067,4,0.067,0.050,2.5,0.10,5.0,0.050),
        Broad=profile(0.100,6,0.100,0.100,5.0,0.20,10.0,0.100),
    }
end
```

Implement modulo distance and wrap-aware progression with invalid/missing values returning `nil`, never zero.

- [ ] **Step 4: Add failing dominant-track, pose, camera-relative, and depth tests**

Use two active tracks with different weights and a stable metadata-key tie. Assert:

```lua
expect(track.key=="rbxassetid://idle|Idle|Core|true|2.0833333","dominant identity")
expect(reason==nil,"valid dominant track")
expect(SEGCFG.controlledRotationGapDeg(identity,yaw90)==90,"SO(3) rotation gap")
expect(SEGCFG.controlledInitialHeadDepth(camera,head,{fieldOfView=70,viewport={828,1792}})==10,"initial depth")
expect(SEGCFG.controlledFeatureFromRawSegment(missingTelemetry)==nil,"missing telemetry fails closed")
```

- [ ] **Step 5: Implement feature extraction without new runtime reads**

Resolve the dominant track from already-captured `snapshot.animation`, preserve identity/name/priority/looped/length/state/speed/weight, calculate start phase and segment advance, and derive:

```lua
{
  id=segment.id, route=segment.route, window=segment.window,
  startTime=segment.startTime, endTime=segment.endTime,
  duration=segment.duration, frameCount=segment.frameCount,
  totalSignedYaw=segment.totalSignedYaw, totalAbsYaw=segment.totalAbsYaw,
  netPitch=segment.netPitch, totalAbsPitch=segment.totalAbsPitch,
  initialLocalHead=<12-number array>,
  initialCamera=<12-number array>, initialPrimary=<12-number array>,
  cameraToPrimary=<12-number rotation array>,
  initialHeadDepth=<studs>, fieldOfView=<degrees>, viewport={<x>,<y>},
  humanoidState=<string>, dominantTrack=<plain table>,
  animationAdvance=<seconds>,
  headHorizontal=segment.head.x,
  primaryHorizontal=segment.primary.x,
  subjectHorizontal=segment.subject.x,
  segmentRef=segment,
}
```

Use the existing first/last `cameraModuleBefore`/`cameraModuleAfter` boundary snapshots, falling back to first/last Controller boundary exactly as `analyzeRawSegment()` does. Do not call Roblox APIs here.

- [ ] **Step 6: Run feature tests and baseline guard rails**

```bash
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --features
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --baseline-only
```

Expected: both PASS, including the wrap-specific test and unchanged baseline digests.

- [ ] **Step 7: Commit feature math**

```bash
git add PCMovementV614_ControlledYawPitchMatching.lua V614_TEMPORAL_POSE_CONTROL_TEST.py
git commit -m "Add V614 temporal pose control features"
```

### Task 3: Build Fixed-Gate Controlled Candidates and Scientific Cost D

**Files:**
- Modify: `PCMovementV614_ControlledYawPitchMatching.lua` pure helper block and immediately after `analyzeRawSegment()`
- Modify: `V614_TEMPORAL_POSE_CONTROL_TEST.py`

**Interfaces:**
- Consumes: two feature tables and one immutable profile table.
- Produces:
  - `SEGCFG.controlledCandidate(touchFeature, relayFeature, profile) -> table?, reason`
  - `SEGCFG.controlledIntegerCost(gaps, profile) -> integer, number`
  - `SEGCFG.buildControlledCandidates(touchFeatures, relayFeatures, profile) -> candidates, rejectionCounts`

- [ ] **Step 1: Add boundary and no-relaxation tests for every gate**

Create a valid synthetic pair exactly on each Moderate boundary, then change one value by `1e-6` and assert rejection with the exact reason:

```lua
local candidate=expectCandidate(validTouch,validRelay,profiles.Moderate)
expect(candidate.durationGap==0.067,"duration boundary passes")
expectRejected(withGap(validRelay,"duration",0.067001),"duration-gap")
expectRejected(withGap(validRelay,"frameCount",5),"frame-count-gap")
expectRejected(withGap(validRelay,"animationAdvance",0.067001),"animation-advance-gap")
expectRejected(withGap(validRelay,"localHeadTranslation",0.050001),"local-head-translation-gap")
expectRejected(withGap(validRelay,"localHeadRotation",2.500001),"local-head-rotation-gap")
expectRejected(withGap(validRelay,"animationPhaseFraction",0.100001),"animation-phase-gap")
expectRejected(withGap(validRelay,"cameraPrimaryRotation",5.000001),"camera-primary-rotation-gap")
expectRejected(withGap(validRelay,"initialHeadDepth",0.050001),"initial-head-depth-gap")
```

Also assert same-direction, baseline 5/1/2-degree gates, exact FOV/viewport, track identity, HumanoidState, speed `<=0.05`, weight `<=0.05`, and fail-closed missing values.

- [ ] **Step 2: Run the candidate test and verify failure**

```bash
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --candidates
```

Expected: FAIL because controlled candidate construction is absent.

- [ ] **Step 3: Implement all individual gates before cost calculation**

Return one stable reason per first failing gate and count every reason in `buildControlledCandidates`. Do not calculate or compare `D` for an ineligible pair.

Use an ordered gate table so rejection reasons cannot vary with `pairs()` iteration:

```lua
local gates={
    {"direction",function() return touch.totalSignedYaw*relay.totalSignedYaw>0 end},
    {"yaw-gap",function() return gaps.yawGap<=profile.yawGap end},
    {"net-pitch-gap",function() return gaps.netPitchGap<=profile.netPitchGap end},
    {"abs-pitch-gap",function() return gaps.absPitchGap<=profile.absPitchGap end},
    {"duration-gap",function() return gaps.durationGap<=profile.durationGap end},
    {"frame-count-gap",function() return gaps.frameCountGap<=profile.frameCountGap end},
    {"animation-advance-gap",function() return gaps.animationAdvanceGap<=profile.animationAdvanceGap end},
    {"local-head-translation-gap",function() return gaps.localHeadTranslationGap<=profile.localHeadTranslationGap end},
    {"local-head-rotation-gap",function() return gaps.localHeadRotationGap<=profile.localHeadRotationGap end},
    {"animation-phase-gap",function() return gaps.animationPhaseFraction<=profile.animationPhaseFraction end},
    {"camera-primary-rotation-gap",function() return gaps.cameraPrimaryRotationGap<=profile.cameraPrimaryRotationGap end},
    {"initial-head-depth-gap",function() return gaps.initialHeadDepthGap<=profile.initialHeadDepthGap end},
}
for _,gate in ipairs(gates) do
    if not gate[2]() then return nil,gate[1] end
end
```

Perform exact camera-config, animation-identity, HumanoidState, speed, and weight checks before this numeric table. Any missing operand returns `missing-<field>`.

- [ ] **Step 4: Implement quantized scientific cost**

For each eligible gap:

```lua
local ratio=math.floor((gap/caliper)*1000000+0.5)/1000000
sumSquared+=ratio*ratio
local integerCost=math.floor(sumSquared*1000000000000+0.5)
local distance=math.sqrt(sumSquared)
```

Store both `integerCost` and report-only `distance`. Stable IDs remain separate tie keys and are not included in `sumSquared`.

- [ ] **Step 5: Prove exact cost and immutable profiles**

Assert a fixture with two normalized gaps of `0.5` yields `D²=0.5`, and mutating the table returned by one `controlledProfiles()` call does not affect the next call. Assert candidate-building never widens a caliper when zero candidates pass.

- [ ] **Step 6: Run candidate, feature, and baseline tests**

```bash
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --candidates
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --features
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --baseline-only
```

Expected: all PASS.

- [ ] **Step 7: Commit fixed candidate gates**

```bash
git add PCMovementV614_ControlledYawPitchMatching.lua V614_TEMPORAL_POSE_CONTROL_TEST.py
git commit -m "Gate V614 controlled temporal pose candidates"
```

### Task 4: Solve Maximum Cardinality, Minimum D, and Deterministic Ties

**Files:**
- Modify: `PCMovementV614_ControlledYawPitchMatching.lua` pure helper block
- Modify: `V614_TEMPORAL_POSE_CONTROL_TEST.py`

**Interfaces:**
- Consumes: eligible candidate edges with stable Touch/relay IDs and integer scientific costs.
- Produces:
  - `SEGCFG.maximumControlledCardinality(touchFeatures, relayFeatures, candidates) -> integer`
  - `SEGCFG.minimumControlledCost(..., requiredCardinality, locked, excluded) -> cost?, edges?`
  - `SEGCFG.solveControlledMatching(touchFeatures, relayFeatures, candidates) -> orderedPairs`
  - `SEGCFG.runControlledProfile(features, profile) -> {pairs, candidates, rejectionCounts, cardinality, totalCost}`

- [ ] **Step 1: Add a maximum-cardinality fixture that defeats greedy selection**

Use edges `T1-R1(cost 1)`, `T1-R2(cost 2)`, and `T2-R1(cost 2)`. Assert the solver returns two pairs (`T1-R2`, `T2-R1`) instead of the one-pair greedy result.

- [ ] **Step 2: Add minimum-cost and deterministic-tie fixtures**

Create two cardinality-two solutions with different total scientific cost and assert the lower cost wins. Then create a symmetric equal-cost graph, execute it with forward and reversed input arrays, and assert identical sorted pair keys:

```lua
local expected={"T1|R1","T2|R2"}
expectKeys(SEGCFG.solveControlledMatching(touch,relay,equalCostEdges),expected)
expectKeys(SEGCFG.solveControlledMatching(reverse(touch),reverse(relay),reverse(equalCostEdges)),expected)
```

- [ ] **Step 3: Run solver tests and verify failure**

```bash
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --solver
```

Expected: FAIL because the optimal solver functions are absent.

- [ ] **Step 4: Implement cardinality and scientific-cost optimization**

Use a bipartite augmenting-path pass for cardinality, followed by min-cost flow for exactly that cardinality. All graph nodes and candidate adjacency lists are sorted by stable IDs before solving.

The min-cost routine has this explicit contract:

```lua
function SEGCFG.minimumControlledCost(touch,relay,candidates,required,locked,excluded)
    -- Validate locked edges are unique and accumulate locked scientific cost.
    -- Build source -> unused Touch -> unused relay -> sink capacity-1 edges.
    -- Add reverse residual edges with negative integer scientific cost.
    -- Run deterministic Bellman-Ford augmentations until `required` total edges.
    -- Return nil when the requested cardinality is infeasible.
    return totalIntegerCost,selectedCandidateEdges
end
```

Distances compare integer cost first, then a stable path-key string, so shortest-path selection is reproducible before global canonicalization.

- [ ] **Step 5: Implement exact canonical tie resolution**

After obtaining optimal cardinality `K` and integer cost `C`, sort candidate keys `(Touch ID, relay ID)`. Iterate in that order; tentatively lock each non-conflicting edge and re-solve the remaining graph. Keep the edge only when a completion still achieves the remaining cardinality and exact remaining scientific cost. This yields the lexicographically smallest ordered pair-key list among all `(K,C)` optima without changing `C`.

```lua
for _,edge in ipairs(sortedCandidates) do
    if not conflicts(edge,locked) then
        local trial=copyAndAppend(locked,edge)
        local trialCost=SEGCFG.minimumControlledCost(touch,relay,candidates,K,trial,excluded)
        if trialCost==C then locked=trial else excluded[edge.key]=true end
    end
    if #locked==K then break end
end
```

- [ ] **Step 6: Sort selected pairs chronologically only after canonical selection**

The solver returns both canonical keys and the report/bootstrap order. Sort report pairs by:

```lua
math.max(pair.touch.endTime,pair.relay.endTime)
```

with Touch ID then relay ID as stable equal-time keys.

- [ ] **Step 7: Run solver tests repeatedly and with reordered inputs**

```bash
for i in 1 2 3 4 5; do python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --solver; done
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --baseline-only
```

Expected: all five solver runs produce the same pair list; baseline guard rails remain green.

- [ ] **Step 8: Commit the deterministic solver**

```bash
git add PCMovementV614_ControlledYawPitchMatching.lua V614_TEMPORAL_POSE_CONTROL_TEST.py
git commit -m "Solve V614 controlled matching deterministically"
```

### Task 5: Freeze 32+32 Before Pruning and Retain the Telemetry Union

**Files:**
- Modify: `PCMovementV614_ControlledYawPitchMatching.lua:1512-1572, 2216-2249`
- Modify: `V614_TEMPORAL_POSE_CONTROL_TEST.py`

**Interfaces:**
- Consumes: all eligible raw segments and fixed profile definitions.
- Produces:
  - `SEGCFG.prepareControlledMatching() -> result`
  - `SEGCFG.getFrozenMatchingResults() -> result?`
  - `SEGCFG.pruneTelemetryToAnalysisUnion(result) -> retentionSummary`
  - `SEGCFG.controlledResults` reset per run.

- [ ] **Step 1: Add failing stop-order and union-retention tests**

Assert the source order inside `stopProbe()` is exactly:

```text
closeCurrentSegment
prepareControlledMatching
pruneTelemetryToAnalysisUnion
probeRunning=false
```

In a synthetic retention fixture, use one baseline-only segment, one Strict/Moderate segment, one Broad-only segment, and one unmatched segment. Assert telemetry remains on the union and is removed only from the unmatched segment.

- [ ] **Step 2: Run retention tests and verify failure**

```bash
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --retention
```

Expected: FAIL because current `stopProbe()` prunes baseline-only telemetry immediately.

- [ ] **Step 3: Reset controlled state without changing acquisition counters**

In `resetCounters()`, set only:

```lua
SEGCFG.controlledResults=nil
SEGCFG.controlledPreparationErrors={}
```

Do not change any standing, phase, sample, segment, or baseline counter.

- [ ] **Step 4: Prepare all feature tables and profile matches before pruning**

`prepareControlledMatching()` must:

1. copy references to all currently eligible Touch and relay segments;
2. call unchanged `SEGCFG.matchSegments()` for baseline;
3. derive every control feature fail-closed;
4. run Strict, Moderate, and Broad independently;
5. freeze candidate/rejection counts, pair lists, and all 32+32 compact features;
6. cache the result so report generation cannot silently rematch modified data.

```lua
function SEGCFG.prepareControlledMatching()
    if SEGCFG.controlledResults then return SEGCFG.controlledResults end
    local result={baseline=SEGCFG.matchSegments(),features={touch={},relay={}},profiles={}}
    for _,route in ipairs({"touch","relay"}) do
        for _,segment in ipairs(segmentStats[route].eligible) do
            local feature,reason=SEGCFG.controlledFeatureFromRawSegment(segment)
            result.features[route][#result.features[route]+1]=feature
            if not feature then
                result.featureErrors=result.featureErrors or {}
                result.featureErrors[reason]=(result.featureErrors[reason] or 0)+1
            end
        end
    end
    for _,name in ipairs({"Strict","Moderate","Broad"}) do
        result.profiles[name]=SEGCFG.runControlledProfile(result.features,SEGCFG.controlledProfiles()[name])
    end
    SEGCFG.controlledResults=result
    return result
end
```

The production implementation must not insert `nil` array holes; invalid feature entries are retained in a separate error list with segment ID and reason.

- [ ] **Step 5: Replace baseline-only pruning with union pruning**

Build `keep[segment]=true` from baseline plus every controlled profile. Clear only `sample.temporalPoseTelemetry` for segments outside this union. Preserve scalar segment data and compact frozen features for all eligible segments.

```lua
for _,pair in ipairs(result.baseline) do keep[pair.touch]=true; keep[pair.relay]=true end
for _,name in ipairs({"Strict","Moderate","Broad"}) do
    for _,pair in ipairs(result.profiles[name].pairs) do
        keep[pair.touch.segmentRef]=true; keep[pair.relay.segmentRef]=true
    end
end
```

- [ ] **Step 6: Update `stopProbe()` only at the post-acquisition boundary**

Change:

```lua
SEGCFG.closeCurrentSegment("probe-stop")
SEGCFG.pruneTelemetryToMatched()
```

to:

```lua
SEGCFG.closeCurrentSegment("probe-stop")
local controlled=SEGCFG.prepareControlledMatching()
SEGCFG.pruneTelemetryToAnalysisUnion(controlled)
```

Do not modify `standingObservation`, `recordPairedSample`, `closeCurrentSegment`, `segmentConsumer`, `updateCoverageState`, or `matchSegments`.

- [ ] **Step 7: Run retention and invariant tests**

```bash
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --retention
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --baseline-only
```

Expected: union retention PASS and all protected digests unchanged.

- [ ] **Step 8: Commit post-acquisition freezing**

```bash
git add PCMovementV614_ControlledYawPitchMatching.lua V614_TEMPORAL_POSE_CONTROL_TEST.py
git commit -m "Retain V614 controlled telemetry union"
```

### Task 6: Export Deduplicated Baseline and Controlled Essential Models

**Files:**
- Modify: `PCMovementV614_ControlledYawPitchMatching.lua:3194-4078`
- Modify: `V614_ESSENTIAL_REPORT_TEST.py`
- Modify: `V614_TEMPORAL_POSE_CONTROL_TEST.py`

**Interfaces:**
- Consumes: frozen matching results and the retained telemetry union.
- Produces:
  - Essential schema `V614-EssentialReportR2-TemporalPoseControl`
  - `model.eligibleFeatures.touch/relay` for all 32+32 compact features
  - `model.segments[stableKey]` with one telemetry projection per retained segment
  - `model.pairSets.Baseline/Strict/Moderate/Broad` referencing stable keys
  - `SEGCFG.analyzeEssentialPairSet(model, name) -> analysis`
  - `SEGCFG.analyzeFullPairSet(rawPairs) -> analysis`
  - `SEGCFG.comparePairSelections(expected, actual) -> {equal, mismatches}`
  - `SEGCFG.resolveAndAnalyzePairSet(model, name) -> pairAnalyses`
  - `SEGCFG.decomposeScreenX(series, beforeField, afterField, totalYaw) -> decomposition?`
  - full-versus-essential matching and analysis parity for every set.

- [ ] **Step 1: Change the test fixture first to require R2 deduplication**

Update the synthetic Essential test to make one segment appear in Baseline, Moderate, and Broad. Assert:

```lua
expect(model.schema=="V614-EssentialReportR2-TemporalPoseControl","R2 schema")
expect(countKeys(model.segments)==uniqueRetainedSegments,"segment telemetry deduplicated")
expect(#model.eligibleFeatures.touch==allTouchFeatures,"all Touch features retained")
expect(#model.eligibleFeatures.relay==allRelayFeatures,"all relay features retained")
expect(#model.pairSets.Baseline==baselineCount,"baseline pair set")
expect(#model.pairSets.Moderate==moderateCount,"Moderate pair set")
```

- [ ] **Step 2: Run the Essential test and verify failure**

```bash
python3 V614_ESSENTIAL_REPORT_TEST.py
```

Expected: FAIL because the production model is still R1 with a single `pairs` array.

- [ ] **Step 3: Build the R2 model from the frozen result**

Serialize every eligible compact feature without `segmentRef`. Intern retained segments by `route|id|window`, reuse the existing camera/joint/animation constant dictionaries, and store pair records as:

```lua
{
  touchKey="touch|touch-1|A1", relayKey="relay|relay-4|B1",
  yawGap=..., netPitchGap=..., absPitchGap=...,
  durationGap=..., frameCountGap=..., animationAdvanceGap=...,
  localHeadTranslationGap=..., localHeadRotationGap=...,
  animationPhaseGap=..., animationPhaseFraction=...,
  cameraPrimaryRotationGap=..., initialHeadDepthGap=...,
  distance=..., integerCost=...,
}
```

Baseline records keep their existing three gaps and omit controlled-only fields.

- [ ] **Step 4: Re-run controlled matching from decoded compact features**

After JSON round-trip, execute the same fixed profiles and solver over `model.eligibleFeatures`. Compare pair keys, integer costs, rejection counts, and cardinalities against frozen runtime results before analyzing telemetry.

```lua
for _,name in ipairs({"Strict","Moderate","Broad"}) do
    local rebuilt=SEGCFG.runControlledProfile(decoded.eligibleFeatures,profiles[name])
    parity.matching[name]=SEGCFG.comparePairSelections(frozen.profiles[name],rebuilt)
end
```

- [ ] **Step 5: Analyze each pair set through a shared accessor**

Replace single-list assumptions in `analyzeEssentialModel()` and `analyzeFullMatchedPairs()` with named pair-set iteration. Preserve the existing Baseline aggregate/bootstrap result under `analysis.profiles.Baseline`. Add Strict, Moderate, and Broad without relabeling Baseline as controlled.

```lua
local output={profiles={}}
for _,name in ipairs({"Baseline","Strict","Moderate","Broad"}) do
    output.profiles[name]=SEGCFG.aggregateEssentialAnalyses(
        SEGCFG.resolveAndAnalyzePairSet(model,name)
    )
end
return output
```

- [ ] **Step 6: Recompute decomposition for Head, PrimaryPart, and subject**

Add a pure helper:

```lua
function SEGCFG.decomposeScreenX(series,beforeField,afterField,totalYaw)
    if totalYaw<=0 or #series==0 then return nil end
    local within,boundary=0,0
    for index,item in ipairs(series) do
        local before,after=item[beforeField],item[afterField]
        if type(before)~="number" or type(after)~="number" then return nil end
        within+=after-before
        if index>1 then
            local previous=series[index-1][afterField]
            if type(previous)~="number" then return nil end
            boundary+=before-previous
        end
    end
    local endpoint=series[#series][afterField]-series[1][beforeField]
    local residual=endpoint-within-boundary
    return {endpoint=endpoint/totalYaw,within=within/totalYaw,
        between=boundary/totalYaw,residual=residual/totalYaw,
        maxAbsResidual=math.abs(residual/totalYaw)}
end
```

Return signed endpoint, within-update, between-frame, residual, and maximum absolute arithmetic residual for each measured point. Assert synthetic exact data yields zero residual for all three points.

- [ ] **Step 7: Prove full-versus-essential parity for matching and analysis**

The updated test must compare:

```lua
expect(parity.matchingEqual,"controlled pair IDs/costs parity")
expect(parity.analysisEqual,"all profile analyses parity")
expect(parity.maxResidual==0,"exact decomposition residual")
```

- [ ] **Step 8: Run Essential, controlled, and baseline tests**

```bash
python3 V614_ESSENTIAL_REPORT_TEST.py
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --all
```

Expected: R2 deduplication, profile parity, decomposition, cyclic wrap, solver, retention, and baseline invariants all PASS.

- [ ] **Step 9: Commit the R2 model and parity gate**

```bash
git add PCMovementV614_ControlledYawPitchMatching.lua V614_ESSENTIAL_REPORT_TEST.py V614_TEMPORAL_POSE_CONTROL_TEST.py
git commit -m "Export V614 controlled essential profile sets"
```

### Task 7: Add Separate Reports and Fail-Closed Scientific Decisions

**Files:**
- Modify: `PCMovementV614_ControlledYawPitchMatching.lua:2350-2644, 4085-4175`
- Modify: `V614_ESSENTIAL_REPORT_TEST.py`
- Modify: `V614_TEMPORAL_POSE_CONTROL_TEST.py`

**Interfaces:**
- Consumes: Baseline/Strict/Moderate/Broad analyses and parity result.
- Produces:
  - `SEGCFG.controlledDecision(profileAnalyses, requiredPairs) -> table`
  - distinct report sections for Baseline and each controlled profile
  - Moderate-primary causal flags with Strict/Broad sensitivity context.

- [ ] **Step 1: Add decision-gate tests before implementation**

Construct three Moderate analyses:

```lua
local insufficient=fakeAnalysis(11,{estimate=-0.01,low=-0.02,high=-0.005,excludesZero=true})
local disappears=fakeAnalysis(12,{estimate=-0.001,low=-0.01,high=0.01,excludesZero=false})
local persists=fakeAnalysis(12,{estimate=-0.01,low=-0.02,high=-0.005,excludesZero=true})
```

Assert:

```lua
expect(insufficientDecision.temporalConfoundResolved=="unproved: insufficient controlled overlap","n<12 temporal")
expect(insufficientDecision.initialPoseConfoundResolved=="unproved: insufficient controlled overlap","n<12 pose")
expect(insufficientDecision.causalMechanismProved==false,"n<12 mechanism blocked")
expect(insufficientDecision.implementationTargetIdentified==false,"n<12 target blocked")
expect(insufficientDecision.v615Justified==false,"n<12 V615 blocked")
expect(insufficientDecision.astra6MaxJustified==false,"n<12 Astra blocked")
expect(disappearsDecision.headHorizontalEffectAfterTemporalControl=="not-supported","CI includes zero")
expect(persistsDecision.headHorizontalEffectAfterTemporalControl=="persists-under-fixed-controls","CI excludes zero")
expect(persistsDecision.causalMechanismProved==false,"persistence alone is not mechanism")
expect(persistsDecision.v615Justified==false and persistsDecision.astra6MaxJustified==false,"no automatic promotion")
```

- [ ] **Step 2: Run decision tests and verify failure**

```bash
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --decisions
```

Expected: FAIL because the current decision is hard-coded to the original matcher.

- [ ] **Step 3: Implement the Moderate-primary fail-closed gate**

Set temporal and initial-pose resolution to true only when Moderate has at least 12 valid controlled pairs and full-versus-essential parity passes. An interval containing zero means “effect not supported under these controls,” never equivalence. An excluding interval means only “persists under fixed controls.”

```lua
if not parity.equal or moderate.pairCount<requiredPairs then
    decision.temporalConfoundResolved="unproved: insufficient controlled overlap"
    decision.initialPoseConfoundResolved="unproved: insufficient controlled overlap"
    decision.headHorizontalEffectAfterTemporalControl="unproved"
elseif not moderate.bootstrap.headHorizontal.excludesZero then
    decision.temporalConfoundResolved=true
    decision.initialPoseConfoundResolved=true
    decision.headHorizontalEffectAfterTemporalControl="not-supported"
else
    decision.temporalConfoundResolved=true
    decision.initialPoseConfoundResolved=true
    decision.headHorizontalEffectAfterTemporalControl="persists-under-fixed-controls"
end
```

Keep these literal booleans for every branch in this revision:

```lua
causalMechanismProved=false
implementationTargetIdentified=false
v615Justified=false
astra6MaxJustified=false
pcEquivalenceClaimAllowed=false
```

- [ ] **Step 4: Identify a decomposition component only for controlled persistence**

When Moderate has `n>=12` and the Head CI excludes zero, compare paired CIs for Head endpoint, within-update, and between-frame components. Report the first component whose controlled CI excludes zero; if none is isolated, use `unproved: persistent endpoint effect not isolated by decomposition`. Do not convert this text into an implementation target.

- [ ] **Step 5: Emit clearly separated report sections**

Generate, in order:

```text
=== V614 BASELINE MATCHER (UNCHANGED) ===
=== V614 CONTROLLED STRICT ===
=== V614 CONTROLLED MODERATE (PRIMARY) ===
=== V614 CONTROLLED BROAD ===
=== V614 CONTROLLED SENSITIVITY SUMMARY ===
=== V614 TEMPORAL + INITIAL-POSE DECISION ===
```

For each controlled profile print pair count; every requested gap distribution; Touch/relay Head, PrimaryPart, and subject horizontal results; paired effect; bootstrap CI; exclusion flag; rejection counts; coverage; and per-pair decomposition/residual.

- [ ] **Step 6: Preserve original evidence without retroactive causal renaming**

Keep the original baseline bootstrap under Baseline and state that the published V614 route-conditioned Head effect remains descriptive until controlled Moderate coverage passes. Record Strict/Broad as sensitivity checks, not alternative primary results.

Keep the reported “emergency mode looked closer to PC” clue in a separate
`qualitative-only` field. Exclude it from feature extraction, candidate gates,
cost, matching, bootstrap, thresholds, and the current decision. Do not start
the emergency-versus-normal static audit in this revision.

- [ ] **Step 7: Run report and decision tests**

```bash
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --decisions
python3 V614_ESSENTIAL_REPORT_TEST.py
```

Expected: every `n<12` promotion test is blocked, report sections are present, and Essential parity remains exact at seven decimals.

- [ ] **Step 8: Commit reporting and decisions**

```bash
git add PCMovementV614_ControlledYawPitchMatching.lua V614_ESSENTIAL_REPORT_TEST.py V614_TEMPORAL_POSE_CONTROL_TEST.py
git commit -m "Report V614 controlled temporal pose decisions"
```

### Task 8: Preserve Mobile Export, Update Loader, and Document the Revision

**Files:**
- Modify: `Loader.lua:1-7`
- Modify: `V614_REPORT_CHUNK_EXPORT_TEST.py`
- Create: `V614_TEMPORAL_POSE_CONTROL_NOTE.md`
- Modify: `PCMovementV614_ControlledYawPitchMatching.lua` version/report schema labels only

**Interfaces:**
- Consumes: final R2 Essential Report string.
- Produces: cache-busted same-filename Loader, one-tap complete clipboard export, unchanged fallback chunks, durable note.

- [ ] **Step 1: Update export-contract tests before Loader revision**

Change the expected Loader revision in both Python tests to:

```lua
local revision="V614-TemporalPoseControlR2-FullClipboardR1"
```

Keep all existing clipboard assertions, including exact reconstructed content and visible success/failure feedback.

- [ ] **Step 2: Run export tests and verify only the revision assertion fails**

```bash
python3 V614_REPORT_CHUNK_EXPORT_TEST.py
```

Expected: FAIL with the missing new Loader revision; transport semantics must not be the failure.

- [ ] **Step 3: Cache-bust Loader without changing the runtime filename**

Keep:

```lua
local url="https://raw.githubusercontent.com/hshsagaga1-commits/movimento-de-pc-no-mobile/main/PCMovementV614_ControlledYawPitchMatching.lua"
```

Change only the revision literal to `V614-TemporalPoseControlR2-FullClipboardR1`.

- [ ] **Step 4: Write the technical note**

Document:

- the unchanged baseline/acquisition hashes and functions;
- the three fixed profiles and formulas/units;
- circular animation phase and dominant-track rules;
- maximum-cardinality/minimum-D/canonical-tie algorithm;
- 32+32 pre-prune freeze and telemetry-union retention;
- Baseline versus controlled report interpretation;
- the `constants.joints=[]` limitation when no joint definitions are captured;
- the fail-closed `n<12` decision;
- the unchanged mobile flow:
  `Loader -> INICIAR -> A1 -> B1 -> B2 -> A2 -> PARAR -> COPIAR REPORT ESSENCIAL COMPLETO`.

- [ ] **Step 5: Run all source, behavior, export, and compile checks**

```bash
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --all
python3 V614_ESSENTIAL_REPORT_TEST.py
python3 V614_REPORT_CHUNK_EXPORT_TEST.py
../tooling/luau-bin/luau-compile PCMovementV614_ControlledYawPitchMatching.lua >/dev/null
../tooling/luau-bin/luau-compile Loader.lua >/dev/null
git diff --check
```

Expected: all PASS and both Luau files compile.

- [ ] **Step 6: Run prohibited-write and API audits**

Compare source changes against checkpoint `a288b72c0ed8a7154045be9d797be677c1bd4d3d`. Assert no new assignment or setter targets Camera/Focus/RootPart/PrimaryPart/Head/Motor6D/animation properties and no new `VirtualInput`, `firesignal`, synthetic `UserInputObject`, `UpdateMouseBehavior`, sensitivity, gain, or physics mutation appears.

Run:

```bash
git diff a288b72c0ed8a7154045be9d797be677c1bd4d3d -- PCMovementV614_ControlledYawPitchMatching.lua Loader.lua
sha256sum PCMovementV20_STABLE.lua PCMovementV500_ScrapFusion.lua PCMovementV604_MultitouchOwnershipProbe.lua
```

Expected: only read-only analysis, post-acquisition retention/reporting, and Loader revision changes; protected hashes exactly match Global Constraints.

- [ ] **Step 7: Commit the validated runtime, Loader, tests, and note**

```bash
git add PCMovementV614_ControlledYawPitchMatching.lua Loader.lua \
  V614_TEMPORAL_POSE_CONTROL_TEST.py V614_ESSENTIAL_REPORT_TEST.py \
  V614_REPORT_CHUNK_EXPORT_TEST.py V614_TEMPORAL_POSE_CONTROL_NOTE.md
git commit -m "Add V614 temporal pose controlled analysis"
```

### Task 9: Final Verification and Publication Gate

**Files:**
- Verify only; no new product file.

**Interfaces:**
- Consumes: fully committed implementation branch.
- Produces: verified main publication or an explicit stop with the failing invariant.

- [ ] **Step 1: Re-run the complete suite from a clean tree**

```bash
git status --short
python3 V614_TEMPORAL_POSE_CONTROL_TEST.py --all
python3 V614_ESSENTIAL_REPORT_TEST.py
python3 V614_REPORT_CHUNK_EXPORT_TEST.py
../tooling/luau-bin/luau-compile PCMovementV614_ControlledYawPitchMatching.lua >/dev/null
../tooling/luau-bin/luau-compile Loader.lua >/dev/null
```

Expected: clean status and all checks PASS.

- [ ] **Step 2: Record final hashes**

```bash
sha256sum PCMovementV614_ControlledYawPitchMatching.lua Loader.lua \
  PCMovementV20_STABLE.lua PCMovementV500_ScrapFusion.lua \
  PCMovementV604_MultitouchOwnershipProbe.lua
git rev-parse HEAD
```

Expected: V20/V500/V604 equal the protected hashes; runtime and Loader receive new documented hashes.

- [ ] **Step 3: Verify publication is a fast-forward from current remote main**

Fetch remote main, confirm no unexpected remote commits, and stop rather than overwrite if fast-forward publication is not possible.

- [ ] **Step 4: Publish and verify remote blobs**

Push the validated commit to `main`, fetch it back, and verify the remote runtime/Loader blobs compile and hash identically to the local committed files.

- [ ] **Step 5: Report the scientific and mobile handoff**

Provide:

- remote commit SHA;
- changed runtime and Loader SHA-256;
- preserved V20/V500/V604 hashes;
- test/compile/invariant results;
- exact fixed calipers and new metrics;
- whether controlled Moderate has enough overlap only after the new iPhone collection;
- mobile steps: `Loader -> A1/B1/B2/A2 -> PARAR -> COPIAR REPORT ESSENCIAL COMPLETO`.

Do not claim temporal or initial-pose resolution from synthetic tests. Those flags require the new real mobile report.
