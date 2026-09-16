# V614 Essential Report Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Export a compact, auditable V614 essential report while proving that analysis from complete in-memory telemetry and analysis from the exported essential model produce identical reported metrics and decisions.

**Architecture:** Keep collection and matching untouched. At export time, project only matched pairs into a versioned plain-table model, deduplicate constant joint/animation/camera metadata, calculate pair-level decomposition from raw telemetry, serialize the model, decode it, rerun the same analysis over decoded data, and refuse a valid report if canonical A/B results differ. Feed only the resulting essential report to the existing lossless 30,000-character chunk transport.

**Tech Stack:** Luau/Roblox runtime, `HttpService:JSONEncode/JSONDecode`, Python source/behavior tests, Luau CLI compiler/runtime, Git/GitHub.

**Spec:** `docs/superpowers/specs/2026-09-16-v614-essential-report-design.md`

## Global Constraints

- Do not modify collection hooks, temporal telemetry capture, V604 ownership/relay, ABBA, segment formation, matching, calipers, bootstrap configuration, gain, sensitivity, camera/character/joint state, physics, or input behavior.
- Do not create V615.
- Keep `PCMovementV20_STABLE.lua`, `PCMovementV500_ScrapFusion.lua`, and `PCMovementV604_MultitouchOwnershipProbe.lua` byte-identical.
- Export only matched-pair evidence needed by a final metric, reconstruction, control, or decision.
- A/B numerical outputs must agree at seven decimal places; categorical decisions must be exactly equal.
- The essential report remains losslessly chunked with each transport envelope at most 30,000 characters.

---

### Task 1: Freeze Scientific Baseline and Add RED Contract Tests

**Files:**
- Create: `V614_ESSENTIAL_REPORT_TEST.py`
- Modify: `V614_REPORT_CHUNK_EXPORT_TEST.py`
- Read: `PCMovementV614_ControlledYawPitchMatching.lua`

**Interfaces:**
- Consumes: current `SEGCFG.matchSegments`, `SEGCFG.segmentClassification`, `PCV614Diagnostics`, and chunk helpers.
- Produces: executable tests requiring `SEGCFG.buildEssentialModel`, `SEGCFG.serializeEssentialModel`, `SEGCFG.analyzeFullMatchedPairs`, `SEGCFG.analyzeEssentialModel`, `SEGCFG.compareAnalysisResults`, and `PCV614EssentialReport`.

- [ ] **Step 1: Record immutable source hashes and protected-region hashes**

Run:

```bash
sha256sum PCMovementV20_STABLE.lua PCMovementV500_ScrapFusion.lua PCMovementV604_MultitouchOwnershipProbe.lua
git show 93e71fdb47baee1aa9f9b2b019cc23609b38d562:PCMovementV614_ControlledYawPitchMatching.lua > /tmp/v614-base.lua
```

Expected protected hashes:

```text
V20  = 634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef
V500 = 5f3b04fccab7e26c322b431162d764a08f17ea29bf566643dd47a4ca6616d096
V604 = 19b80d8241b367808a8b815d3c8ef6668a0c4e53454569b9652e2bbae132a571
```

- [ ] **Step 2: Write the failing essential-report contract test**

Create `V614_ESSENTIAL_REPORT_TEST.py` so it extracts a production helper block delimited by:

```lua
-- BEGIN V614 ESSENTIAL REPORT PURE HELPERS
-- END V614 ESSENTIAL REPORT PURE HELPERS
```

The generated Luau test must construct two Touch and two Relay synthetic matched segments containing:

```lua
local pairs={
  {yawGap=0.1,netPitchGap=0.02,absPitchGap=0.03,
   touch=syntheticSegment("touch","A1",1),
   relay=syntheticSegment("relay","B1",2)},
  {yawGap=0.2,netPitchGap=0.01,absPitchGap=0.04,
   touch=syntheticSegment("touch","A2",3),
   relay=syntheticSegment("relay","B2",4)},
}
```

Assert all of the following:

```lua
expect(#model.pairs==2,"matched-only pair count")
expect(#model.constants.joints==1,"constant joint definition deduplication")
expect(#model.constants.animations==1,"track metadata deduplication")
expect(model.omissions.unmatchedAcceptedFrames~=nil,"omission manifest")
expect(model.pairs[1].touch.boundaries.start~=nil,"start boundary")
expect(model.pairs[1].touch.boundaries.finish~=nil,"finish boundary")
expect(model.pairs[1].touch.series[1].jointTransform~=nil,"variable joint series")
expect(SEGCFG.compareAnalysisResults(fullAnalysis,essentialAnalysis).equal,"A/B parity")
```

The Python layer must also assert that export calls `PCV614EssentialReport()` and does not call `PCV614Report(true)`.

- [ ] **Step 3: Run the new test and verify RED**

Run:

```bash
python3 V614_ESSENTIAL_REPORT_TEST.py
```

Expected: failure stating that the production essential helper block or `PCV614EssentialReport` is missing.

- [ ] **Step 4: Update the existing chunk test expectation only after the new Loader revision exists**

Change its required revision string to:

```python
'local revision="V614-TemporalPoseTelemetryR1-EssentialReportR1"'
```

Do not weaken any exact reconstruction or 30,000-character assertions.

- [ ] **Step 5: Commit the RED tests**

```bash
git add V614_ESSENTIAL_REPORT_TEST.py V614_REPORT_CHUNK_EXPORT_TEST.py
git commit -m "Test V614 essential report contract"
```

### Task 2: Build the Canonical Matched-Pair Model

**Files:**
- Modify: `PCMovementV614_ControlledYawPitchMatching.lua`
- Test: `V614_ESSENTIAL_REPORT_TEST.py`

**Interfaces:**
- Consumes: `pairs: {touch: Segment, relay: Segment, yawGap: number, netPitchGap: number, absPitchGap: number}[]` and diagnostics table.
- Produces:
  - `SEGCFG.buildEssentialModel(pairs, diagnostics) -> table`
  - `SEGCFG.serializeEssentialModel(model) -> string`
  - `SEGCFG.deserializeEssentialModel(json) -> table`
  - dictionary references for joint definitions, animation metadata, and camera configuration.

- [ ] **Step 1: Add pure canonicalization helpers**

Inside the delimited helper block implement:

```lua
function SEGCFG.roundEssential(value)
    return type(value)=="number" and math.floor(value*10000000+(value>=0 and 0.5 or -0.5))/10000000 or value
end

function SEGCFG.arrayKey(values)
    local out={}
    for i,value in ipairs(values or {}) do out[i]=tostring(SEGCFG.roundEssential(value)) end
    return table.concat(out,",")
end

function SEGCFG.internConstant(dictionary,index,key,value)
    local existing=index[key]
    if existing then return existing end
    local id=#dictionary+1
    dictionary[id]=value; index[key]=id
    return id
end
```

Use stable sorted track identity `AnimationId|Name|Priority|Looped|Length` and stable joint identity `Name|Part0|Part1|C0|C1`.

- [ ] **Step 2: Project only matched segments**

Implement `buildEssentialModel` with this top-level schema:

```lua
{
  schema="V614-EssentialReportR1",
  run=runMetadata, config=scientificConfig, integrity=integrityCounters,
  windows={A1=windowA1,B1=windowB1,B2=windowB2,A2=windowA2},
  constants={camera={},joints={},animations={}},
  pairs=matchedPairRecords, analysis=analysisResult,
  omissions=omissionManifest, parity=parityResult
}
```

For each pair, project Touch and Relay with:

```lua
{
  id=segment.id, route=segment.route, window=segment.window,
  startFrame=segment.startFrame, endFrame=segment.endFrame,
  startTime=segment.startTime, endTime=segment.endTime,
  duration=segment.duration, frameCount=segment.frameCount,
  totalSignedYaw=segment.totalSignedYaw, totalAbsYaw=segment.totalAbsYaw,
  netPitch=segment.netPitch, totalAbsPitch=segment.totalAbsPitch,
  yawTrajectory=segment.yawTrajectory, pitchTrajectory=segment.pitchTrajectory,
  screen={primary=primaryMetric,head=headMetric,subject=subjectMetric,
          returnedPrimary=returnedPrimaryMetric,returnedHead=returnedHeadMetric,
          returnedSubject=returnedSubjectMetric},
  geometry={subjectToPrimaryStart=subjectToPrimaryStart,
            subjectToPrimaryEnd=subjectToPrimaryEnd,
            subjectToHeadStart=subjectToHeadStart,
            subjectToHeadEnd=subjectToHeadEnd,
            primaryToHeadStart=primaryToHeadStart,
            primaryToHeadEnd=primaryToHeadEnd},
  boundaries={start=startBoundaryRecord,finish=finishBoundaryRecord},
  series=perFrameAnalysisRecords
}
```

Do not iterate over `pairedStats[phase].samples`, rejected segments, or unmatched eligible segments when building `pairs`.

- [ ] **Step 3: Deduplicate constant state**

Each boundary stores full Camera/Primary/Head/PrimaryToHead values and only joint Transform plus a joint-definition ID. Animation entries store a metadata ID plus TimePosition, WeightCurrent, WeightTarget, Speed and IsPlaying. FOV/viewport store a camera-config ID.

- [ ] **Step 4: Emit the omission manifest**

Populate exact keys and reasons:

```lua
omissions={
  unmatchedAcceptedFrames="not consumed by matched-pair analysis, controls, bootstrap, or decisions",
  rejectedSegments="only rejection counters/reasons participate; pose samples do not",
  unmatchedEligibleSegments="matching counts/ranges are retained; telemetry is not selected",
  repeatedJointConstants="deduplicated in constants.joints and referenced by ID",
  repeatedAnimationMetadata="deduplicated in constants.animations and referenced by ID",
  repeatedCameraConfig="deduplicated in constants.camera and referenced by ID",
  guiStateMessages="not consumed by any scientific metric or decision",
  redundantDebugEvidence="final counters and integrity summaries are retained",
}
```

- [ ] **Step 5: Serialize through HttpService without lossy formatting**

Production wrappers:

```lua
function SEGCFG.serializeEssentialModel(model)
    return HttpService:JSONEncode(model)
end
function SEGCFG.deserializeEssentialModel(text)
    return HttpService:JSONDecode(text)
end
```

The pure helper test uses injected JSON round-trip helpers so the same plain-table contract is exercised outside Roblox.

- [ ] **Step 6: Run the focused test and verify GREEN for model construction**

Run:

```bash
python3 V614_ESSENTIAL_REPORT_TEST.py
```

Expected: model/dictionary/omission assertions pass; report wiring assertion may remain red until Task 4.

- [ ] **Step 7: Commit the model builder**

```bash
git add PCMovementV614_ControlledYawPitchMatching.lua V614_ESSENTIAL_REPORT_TEST.py
git commit -m "Build canonical V614 essential model"
```

### Task 3: Add Full-vs-Essential Causal Analysis and Parity Gate

**Files:**
- Modify: `PCMovementV614_ControlledYawPitchMatching.lua`
- Test: `V614_ESSENTIAL_REPORT_TEST.py`

**Interfaces:**
- Consumes: raw matched pairs or decoded essential pairs.
- Produces:
  - `SEGCFG.analyzeFullMatchedPairs(pairs) -> table`
  - `SEGCFG.analyzeEssentialModel(model) -> table`
  - `SEGCFG.compareAnalysisResults(a,b) -> {equal:boolean,mismatches:string[]}`

- [ ] **Step 1: Add RED decomposition assertions**

Extend the synthetic fixture with known camera, PrimaryPart, Head, local Head,
joint, animation and screen-coordinate changes. Assert exact expected values for:

```lua
analysis.pairs[1].touch.duration
analysis.pairs[1].touch.frameCount
analysis.pairs[1].touch.headWithinXPerYaw
analysis.pairs[1].touch.headBoundaryXPerYaw
analysis.pairs[1].touch.rootTranslation
analysis.pairs[1].touch.localHeadTranslation
analysis.pairs[1].touch.joints.Neck.translation
analysis.pairs[1].touch.animations[1].timeAdvance
analysis.pairs[1].touch.projection.cameraOnlyHeadDX
analysis.pairs[1].touch.projection.poseOnlyHeadDX
```

Run the test and confirm it fails because analysis functions are absent.

- [ ] **Step 2: Implement a shared segment analyzer over an accessor**

Implement:

```lua
function SEGCFG.analyzeSegment(accessor,segment)
    -- returns temporal, root, local-head, joints, animations, projection,
    -- screen-identity and initial-state fields using only accessor methods
end
```

The raw accessor reads `segment.samples[*].temporalPoseTelemetry`; the essential
accessor reads decoded `boundaries` and `series`. Compute:

- endpoint and path translation/rotation for PrimaryPart and local Head;
- joint Transform endpoint/path translation/rotation for Neck/Waist/RootJoint;
- per-track TimePosition advance, weight change, speed and playing-state changes;
- within-update and inter-frame X/Y screen terms for Head/Primary/subject;
- start/end depth and camera-only, pose-only and combined endpoint projections;
- duration, frame count, yaw rate and initial camera/pose/animation state.

- [ ] **Step 3: Produce pair-by-pair and aggregate results**

`analyzeFullMatchedPairs` and `analyzeEssentialModel` must return the same schema:

```lua
{
  pairs=pairAnalysisRecords,
  aggregates={root=rootAggregate,localHead=localHeadAggregate,
    joints=jointAggregate,animation=animationAggregate,projection=projectionAggregate},
  bootstrap={headHorizontal=headBootstrap,primaryHorizontal=primaryBootstrap,
    subjectHorizontal=subjectBootstrap},
  decisions={temporalConfoundResolved=temporalDecision,
    initialPoseConfoundResolved=initialPoseDecision,
    rootMotionContribution=rootDecision,jointTransformContribution=jointDecision,
    animationProgressContribution=animationDecision,
    projectionDepthContribution=projectionDecision,
    headHorizontalEffectAfterTemporalControl=headDecision,
    firstConcreteGeometricDivergence=firstDivergence,causalMechanismProved=false,
    implementationTargetIdentified=false,v615Justified=false,
    astra6MaxJustified=false}
}
```

Do not invent a post-hoc temporal/pose threshold. If the existing pairs do not
identify a component independently, record quantitative contributions and set
the relevant decision to `unproved` with the unresolved variable.

- [ ] **Step 4: Implement canonical parity comparison**

Recursively sort table keys. Compare numbers after seven-decimal rounding and
strings/booleans exactly. Return every mismatched path. A missing input in the
decoded model must make the negative fixture fail parity.

- [ ] **Step 5: Run RED/GREEN parity cycle**

Run:

```bash
python3 V614_ESSENTIAL_REPORT_TEST.py
```

Expected final output includes:

```text
PASS: V614 full and essential analyses are identical at report precision
PASS: missing essential input is detected by parity gate
```

- [ ] **Step 6: Commit the analysis and gate**

```bash
git add PCMovementV614_ControlledYawPitchMatching.lua V614_ESSENTIAL_REPORT_TEST.py
git commit -m "Verify V614 full essential analysis parity"
```

### Task 4: Replace Final Report Construction and Wire Chunk Export

**Files:**
- Modify: `PCMovementV614_ControlledYawPitchMatching.lua`
- Modify: `Loader.lua`
- Test: `V614_ESSENTIAL_REPORT_TEST.py`
- Test: `V614_REPORT_CHUNK_EXPORT_TEST.py`

**Interfaces:**
- Consumes: essential model, serialized JSON, A/B analysis and diagnostics.
- Produces: `getgenv().PCV614EssentialReport() -> string`; `PCV614Report` becomes a compatibility alias returning the essential report.

- [ ] **Step 1: Add a count-only legacy sink**

Refactor the old report emitter so its sections can call either:

```lua
sink:add(line)                 -- retained report
countSink:add(line)            -- increments UTF-8 chars plus newline only
```

The count-only path must not retain `lines`, a legacy full string, or chunk
payloads. It returns the exact hypothetical old `fullReportChars`.

- [ ] **Step 2: Build the essential report once**

Implement `PCV614EssentialReport` to append:

1. identification/configuration/integrity and window summaries;
2. matched pair and segment summaries;
3. human-readable pair-by-pair decomposition and aggregate/bootstrap results;
4. omission manifest;
5. `=== V614 ESSENTIAL MODEL JSON ===` followed by the canonical JSON;
6. final causal decisions and A/B parity fields;
7. size fields.

Calculate size fields with a two-pass fixed-point build because
`essentialReportChars` and `essentialChunks` appear inside the report. Repeat
until the values stabilize, with a maximum of four passes and an error if they
do not.

- [ ] **Step 3: Add exact size and parity fields**

The final report must include:

```text
fullReportChars = <legacy count-only result>
essentialReportChars = <UTF-8 character count of this exact report>
reductionPercent = <seven-decimal percentage>
essentialChunks = <count using 29,500-character payloads>
analysisAFullTelemetryDigest = <canonical digest/string>
analysisBEssentialDigest = <same canonical digest/string>
analysisParity = true
analysisParityMismatches = none
```

Set essential validation false if parity is false.

- [ ] **Step 4: Route export only to the essential report**

Change:

```lua
local fullReport=getgenv().PCV614Report(true)
```

to:

```lua
local fullReport=getgenv().PCV614EssentialReport()
```

Keep `splitReportPayloads`, envelope markers, report ID, navigation and exact
reconstruction checks unchanged.

- [ ] **Step 5: Cache-bust Loader without changing target filename**

Set:

```lua
local revision="V614-TemporalPoseTelemetryR1-EssentialReportR1"
```

- [ ] **Step 6: Run both tests and compile**

Run:

```bash
python3 V614_ESSENTIAL_REPORT_TEST.py
python3 V614_REPORT_CHUNK_EXPORT_TEST.py
../tooling/luau-bin/luau-compile PCMovementV614_ControlledYawPitchMatching.lua >/dev/null
../tooling/luau-bin/luau-compile Loader.lua >/dev/null
```

Expected: all tests pass and both files compile.

- [ ] **Step 7: Commit report wiring**

```bash
git add PCMovementV614_ControlledYawPitchMatching.lua Loader.lua V614_ESSENTIAL_REPORT_TEST.py V614_REPORT_CHUNK_EXPORT_TEST.py
git commit -m "Export V614 essential causal report"
```

### Task 5: Document Omissions and Verify Scientific Immutability

**Files:**
- Create: `V614_ESSENTIAL_REPORT_NOTE.md`
- Modify: no scientific runtime sections.

**Interfaces:**
- Consumes: final implementation and test output.
- Produces: durable note with removed categories, reasons, size/parity fields, hashes and mobile workflow.

- [ ] **Step 1: Write the technical note**

Document:

- every omitted category and why no metric/control/reconstruction/decision uses it;
- constant dictionaries and variable series retained;
- exact A/B comparison method and validation behavior;
- `fullReportChars`, `essentialReportChars`, `reductionPercent`, and
  `essentialChunks` as runtime-populated fields rather than invented static
  values;
- no V615, no correction, and no scientific configuration change;
- mobile flow: stop, generate essential report, copy all chunks by report ID.

- [ ] **Step 2: Diff-audit protected runtime regions**

Use a Python verifier to compare commit
`93e71fdb47baee1aa9f9b2b019cc23609b38d562` against working tree for:

- telemetry capture functions;
- hook installation and callback bodies;
- standing gate and segment creation;
- `matchSegments` and caliper constants;
- ABBA window state transitions;
- V604 relay calls.

Only report-building, export-cache reset/UI labels, pure analysis and Loader
revision may differ.

- [ ] **Step 3: Run prohibited-write and preserved-hash audit**

Run:

```bash
rg -n 'Camera\.CFrame\s*=|Camera\.Focus\s*=|PrimaryPart\.CFrame\s*=|Head\.CFrame\s*=|RootPart\.CFrame\s*=|\.Transform\s*=|MouseSensitivity\s*=|PreferredInput\s*=|MouseBehavior\s*=|RotationType\s*=|AutoRotate\s*=' PCMovementV614_ControlledYawPitchMatching.lua
sha256sum PCMovementV20_STABLE.lua PCMovementV500_ScrapFusion.lua PCMovementV604_MultitouchOwnershipProbe.lua
```

Expected: no new prohibited writes and the three known hashes unchanged.

- [ ] **Step 4: Run the complete verification suite**

```bash
python3 V614_ESSENTIAL_REPORT_TEST.py
python3 V614_REPORT_CHUNK_EXPORT_TEST.py
../tooling/luau-bin/luau-compile PCMovementV614_ControlledYawPitchMatching.lua >/dev/null
../tooling/luau-bin/luau-compile Loader.lua >/dev/null
git diff --check
```

- [ ] **Step 5: Commit documentation**

```bash
git add V614_ESSENTIAL_REPORT_NOTE.md
git commit -m "Document V614 essential report audit"
```

### Task 6: Publish and Verify Main

**Files:**
- Publish all commits after remote base `93e71fdb47baee1aa9f9b2b019cc23609b38d562`.

**Interfaces:**
- Consumes: verified local tree.
- Produces: fast-forward GitHub `main` commit and verified remote blobs.

- [ ] **Step 1: Confirm remote base has not moved**

Fetch `refs/heads/main`; expected SHA before publication:

```text
93e71fdb47baee1aa9f9b2b019cc23609b38d562
```

If different, stop and reconcile without force-pushing.

- [ ] **Step 2: Run final verification immediately before publication**

Repeat both Python tests, both Luau compiles, `git diff --check`, status, hashes
and protected-region audit. Do not publish on any failure.

- [ ] **Step 3: Publish as a non-force fast-forward**

Create blobs/tree/commit on the verified remote base and update `main` with
`force=false`.

- [ ] **Step 4: Verify remote commit and Loader**

Fetch the resulting commit/tree and `Loader.lua`. Confirm the runtime blob,
note, tests and cache revision match the local verified artifacts.

- [ ] **Step 5: Report final artifacts**

Provide the remote commit SHA, runtime/Loader SHA-256, preserved V20/V500/V604
hashes, tests executed, and links to runtime, Loader, note and tests. Do not
claim a causal mechanism or create V615.
