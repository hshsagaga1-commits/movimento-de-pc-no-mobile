#!/usr/bin/env python3
"""Guard the V614 baseline and acquisition invariants.

This runner intentionally treats the existing V614 acquisition and greedy
matcher as read-only.  It checks the checkpoint digests before extracting the
matcher into a tiny standalone Luau characterization fixture.
"""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from typing import NoReturn


ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "PCMovementV614_ControlledYawPitchMatching.lua"
BASELINE_CHECKPOINT = "a288b72c0ed8a7154045be9d797be677c1bd4d3d"

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
    "PCMovementV20_STABLE.lua":
        "634ca4312a96ebb3b0ce556d083264a67817f0066cab4168c0256b7b95d542ef",
    "PCMovementV500_ScrapFusion.lua":
        "5f3b04fccab7e26c322b431162d764a08f17ea29bf566643dd47a4ca6616d096",
    "PCMovementV604_MultitouchOwnershipProbe.lua":
        "19b80d8241b367808a8b815d3c8ef6668a0c4e53454569b9652e2bbae132a571",
}

REQUIRED_LITERALS = (
    "local STABILIZE_SECONDS=1.50",
    "local STABLE_CONSECUTIVE_FRAMES=12",
    "targetYaw=60,maxYaw=120,minFrames=3,maxFrameGap=3,maxDuration=1.25",
    'sequence={"A1","B1","B2","A2"}',
    'route={A1="touch",A2="touch",B1="relay",B2="relay"}',
)


class InvariantFailure(RuntimeError):
    """A source or characterization invariant did not hold."""


def fail(message: str) -> NoReturn:
    raise InvariantFailure(message)


def extract_section(source: str, name: str) -> str:
    """Extract an anchored region, retaining its start anchor exactly."""

    start_anchor, end_anchor, _ = PROTECTED_SECTIONS[name]
    start = source.find(start_anchor)
    if start < 0:
        fail(f"{name} start anchor is missing")
    if source.find(start_anchor, start + len(start_anchor)) >= 0:
        fail(f"{name} start anchor is ambiguous")
    end = source.find(end_anchor, start + len(start_anchor))
    if end < 0:
        fail(f"{name} end anchor is missing")
    return source[start:end]


def check_source_invariants(source: str) -> None:
    for name, (_, _, expected_digest) in PROTECTED_SECTIONS.items():
        actual_digest = hashlib.sha256(
            extract_section(source, name).encode("utf-8")
        ).hexdigest()
        if actual_digest != expected_digest:
            fail(
                f"{name} digest changed: expected {expected_digest}, got {actual_digest}"
            )
    for literal in REQUIRED_LITERALS:
        if literal not in source:
            fail(f"required literal is missing: {literal}")


def check_protected_files() -> None:
    for filename, expected_digest in PROTECTED_FILES.items():
        path = ROOT / filename
        if not path.is_file():
            fail(f"protected file is missing: {filename}")
        actual_digest = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual_digest != expected_digest:
            fail(
                f"{filename} hash changed: expected {expected_digest}, got {actual_digest}"
            )


def luau_binary() -> Path:
    configured = os.environ.get("LUAU_BIN")
    binary = (
        Path(configured)
        if configured
        else ROOT.parent / "tooling" / "luau-bin" / "luau"
    )
    if not binary.is_file():
        fail(f"Luau binary is missing: {binary}")
    return binary


def run_matcher_characterization(source: str) -> None:
    matcher = extract_section(source, "matchSegments")
    program = """\
local SEGCFG={
    matchYawGap=5.0,matchNetPitchGap=1.0,matchAbsPitchGap=2.0,
}
""" + matcher + r'''

local function expect(condition,message)
    if not condition then error(message,0) end
end

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
expect(math.abs(pairs[1].yawGap-0.1)<1e-12 and math.abs(pairs[2].yawGap-0.2)<1e-12,
    "baseline yaw gaps")
print("PASS: V614 baseline greedy matcher characterization is unchanged")
'''

    with tempfile.TemporaryDirectory(prefix="v614-baseline-test-") as temp_dir:
        test_path = Path(temp_dir) / "baseline_matcher_test.luau"
        test_path.write_text(program, encoding="utf-8")
        completed = subprocess.run(
            [str(luau_binary()), str(test_path)],
            check=False,
            text=True,
            capture_output=True,
        )
    if completed.returncode != 0:
        details = (completed.stdout + completed.stderr).strip()
        suffix = f": {details}" if details else ""
        fail(f"baseline matcher characterization failed{suffix}")
    if completed.stdout != "PASS: V614 baseline greedy matcher characterization is unchanged\n":
        fail(f"unexpected matcher output: {completed.stdout!r}")
    print(completed.stdout, end="")


def extract_essential_helpers(source: str) -> str:
    start_anchor = "-- BEGIN V614 ESSENTIAL REPORT PURE HELPERS"
    end_anchor = "-- END V614 ESSENTIAL REPORT PURE HELPERS"
    start = source.find(start_anchor)
    end = source.find(end_anchor, start + len(start_anchor))
    if start < 0 or end < 0:
        fail("essential helper anchors are missing")
    return source[start:end]


def extract_controlled_preparation(source: str) -> str:
    start_anchor = "-- BEGIN V614 CONTROLLED PREPARATION"
    end_anchor = "-- END V614 CONTROLLED PREPARATION"
    start = source.find(start_anchor)
    end = source.find(end_anchor, start + len(start_anchor))
    if start < 0 or end < 0:
        fail("controlled preparation anchors are missing")
    return source[start:end]


def run_feature_characterization(source: str) -> None:
    helpers = extract_essential_helpers(source)
    program = r'''local SEGCFG={}
''' + helpers + r'''

local function expect(condition,message)
    if not condition then error(message,0) end
end

local profiles=SEGCFG.controlledProfiles()
expect(profiles.Strict.durationGap==0.034 and profiles.Strict.frameCountGap==2,"Strict literals")
expect(profiles.Moderate.durationGap==0.067 and profiles.Moderate.frameCountGap==4,"Moderate literals")
expect(profiles.Broad.durationGap==0.100 and profiles.Broad.frameCountGap==6,"Broad literals")
profiles.Strict.durationGap=99
expect(SEGCFG.controlledProfiles().Strict.durationGap==0.034,"fresh profile tables")
expect(SEGCFG.controlledCircularPhaseGap(1.95,0.05,2,true)==0.1,"cyclic phase wrap")
expect(SEGCFG.controlledCircularPhaseGap(0.25,1.25,2,true)==1,"half-cycle distance")
expect(SEGCFG.controlledCircularPhaseGap(1.95,0.05,2,false)==1.9,"non-looped linear phase")
expect(SEGCFG.controlledAnimationAdvance(1.95,0.05,2,true)==0.1,"animation advance wrap")
expect(SEGCFG.controlledCircularPhaseGap(nil,0,2,true)==nil,"invalid cyclic phase")
expect(SEGCFG.controlledAnimationAdvance(0,1,nil,true)==nil,"invalid animation timing")

local identity={0,0,0,1,0,0,0,1,0,0,0,1}
local yaw90={0,0,0,0,0,-1,0,1,0,1,0,0}
local animation={humanoidState="Running",tracks={
    {animationId="rbxassetid://walk",name="Walk",priority="Core",looped=true,length=1,
        timePosition=0.4,speed=1,weightCurrent=0.6,weightTarget=0.6,isPlaying=true},
    {animationId="rbxassetid://idle",name="Idle",priority="Core",looped=true,length=2.0833333,
        timePosition=1.95,speed=1,weightCurrent=0.6,weightTarget=0.6,isPlaying=true},
    {animationId="rbxassetid://faint",name="Faint",priority="Core",looped=true,length=1,
        timePosition=0.2,speed=1,weightCurrent=0.1,weightTarget=0.1,isPlaying=true},
}}
local track,reason=SEGCFG.controlledDominantTrack(animation)
expect(track and track.key=="rbxassetid://idle|Idle|Core|true|2.0833333","dominant identity")
expect(reason==nil,"valid dominant track")
local missingMetadata={tracks={{name="Idle",priority="Core",looped=true,length=2,timePosition=0,
    speed=1,weightCurrent=1,weightTarget=1,isPlaying=true}}}
expect(SEGCFG.controlledDominantTrack(missingMetadata)==nil,"missing animation metadata fails closed")
local validIdle=SEGCFG.deepCopyEssential(animation.tracks[2]); validIdle.weightCurrent=0.2
local malformed=SEGCFG.deepCopyEssential(missingMetadata.tracks[1]); malformed.weightCurrent=0.9
local mixedTrack,mixedReason=SEGCFG.controlledDominantTrack({tracks={validIdle,malformed}})
expect(mixedTrack==nil and mixedReason=="invalid active animation track",
    "malformed heavier active track must not disappear before dominance ranking")
for _,field in ipairs({"isPlaying","weightCurrent","length","timePosition","speed","weightTarget"}) do
    local uncertain=SEGCFG.deepCopyEssential(animation.tracks[1]); uncertain[field]=nil
    expect(SEGCFG.controlledDominantTrack({tracks={validIdle,uncertain}})==nil,
        "uncertain mixed track fails closed: "..field)
end
local inactive=SEGCFG.deepCopyEssential(malformed); inactive.isPlaying=false
expect(SEGCFG.controlledDominantTrack({tracks={validIdle,inactive}})~=nil,
    "explicitly inactive malformed track cannot dominate")
expect(SEGCFG.controlledDominantTrack({tracks={[1]=validIdle,[3]=malformed}})==nil,
    "sparse track capture fails closed")

local duplicateMetadata={tracks={
    {animationId="rbxassetid://dup",name="Dup",priority="Core",looped=true,length=2,timePosition=0,
        speed=1,weightCurrent=1,weightTarget=1,isPlaying=true},
    {animationId="rbxassetid://dup",name="Dup",priority="Core",looped=true,length=2,timePosition=1,
        speed=1,weightCurrent=1,weightTarget=1,isPlaying=true},}}
expect(SEGCFG.controlledDominantTrack(duplicateMetadata)==nil,"duplicate animation identity fails closed")
expect(SEGCFG.controlledRotationGapDeg(identity,yaw90)==90,"SO(3) rotation gap")
local cameraToYaw=SEGCFG.controlledRelativeRotation(yaw90,identity)
expect(cameraToYaw and cameraToYaw[4]==0 and cameraToYaw[6]==1 and cameraToYaw[10]==-1,"camera-to-primary relative rotation")
local camera={0,0,0,1,0,0,0,1,0,0,0,1}
local head={0,0,-10,1,0,0,0,1,0,0,0,1}
expect(SEGCFG.controlledInitialHeadDepth(camera,head,{fieldOfView=70,viewport={828,1792}})==10,"initial depth")

local function snapshot(timePosition)
    return {fieldOfView=70,viewport={828,1792},cameraCFrame=camera,
        primaryCFrame=identity,headCFrame=head,primaryToHead=identity,
        animation={humanoidState="Running",tracks={{animationId="rbxassetid://idle",name="Idle",
            priority="Core",looped=true,length=2.0833333,timePosition=timePosition,speed=1,
            weightCurrent=0.6,weightTarget=0.6,isPlaying=true}}}}
end
local missingTelemetry={id="missing",samples={{}}}
expect(SEGCFG.controlledFeatureFromRawSegment(missingTelemetry)==nil,"missing telemetry fails closed")
local rawSegment={id="s1",route="touch",window="A1",startTime=2,endTime=2.1,duration=0.1,frameCount=4,
    totalSignedYaw=60,totalAbsYaw=60,netPitch=0,totalAbsPitch=1,
    head={x=101},primary={x=100},subject={x=99},samples={{temporalPoseTelemetry={
        cameraModuleBefore=snapshot(1.95),cameraModuleAfter=snapshot(0.05),controllerCalls={}}}}}
local feature,featureReason=SEGCFG.controlledFeatureFromRawSegment(rawSegment)
expect(feature and featureReason==nil,"feature extraction")
expect(feature.animationAdvance==0.1833333,"feature animation advance")
expect(feature.humanoidState=="Running" and feature.dominantTrack.key=="rbxassetid://idle|Idle|Core|true|2.0833333","feature animation metadata")
expect(feature.initialHeadDepth==10 and feature.fieldOfView==70 and feature.viewport[1]==828 and feature.viewport[2]==1792,"feature camera metadata")
expect(feature.headHorizontal==101 and feature.primaryHorizontal==100 and feature.subjectHorizontal==99 and feature.segmentRef==rawSegment,"feature segment fields")
expect(#feature.initialCamera==12 and #feature.initialPrimary==12 and #feature.initialLocalHead==12 and #feature.cameraToPrimary==12,"feature pose arrays")
local function expectInvalidSegment(segment,message)
    expect(SEGCFG.controlledFeatureFromRawSegment(segment)==nil,message)
end
local malformedPose=SEGCFG.deepCopyEssential(rawSegment)
malformedPose.samples[1].temporalPoseTelemetry.cameraModuleBefore.cameraCFrame[4]="not-a-number"
expectInvalidSegment(malformedPose,"nonnumeric pose fails closed")
local nanPose=SEGCFG.deepCopyEssential(rawSegment)
nanPose.samples[1].temporalPoseTelemetry.cameraModuleBefore.cameraCFrame[4]=0/0
expectInvalidSegment(nanPose,"NaN pose fails closed")
local missingDuration=SEGCFG.deepCopyEssential(rawSegment)
missingDuration.duration=nil
expectInvalidSegment(missingDuration,"missing duration fails closed")
local missingMetric=SEGCFG.deepCopyEssential(rawSegment)
missingMetric.head.x=nil
expectInvalidSegment(missingMetric,"missing head metric fails closed")
local missingHumanoidState=SEGCFG.deepCopyEssential(rawSegment)
missingHumanoidState.samples[1].temporalPoseTelemetry.cameraModuleBefore.animation.humanoidState=nil
expectInvalidSegment(missingHumanoidState,"missing humanoid state fails closed")
local missingSpeed=SEGCFG.deepCopyEssential(rawSegment)
missingSpeed.samples[1].temporalPoseTelemetry.cameraModuleBefore.animation.tracks[1].speed=nil
expectInvalidSegment(missingSpeed,"missing track speed fails closed")
local missingWeight=SEGCFG.deepCopyEssential(rawSegment)
missingWeight.samples[1].temporalPoseTelemetry.cameraModuleBefore.animation.tracks[1].weightCurrent=nil
expectInvalidSegment(missingWeight,"missing track weight fails closed")
local missingTrackState=SEGCFG.deepCopyEssential(rawSegment)
missingTrackState.samples[1].temporalPoseTelemetry.cameraModuleBefore.animation.tracks[1].isPlaying=nil
expectInvalidSegment(missingTrackState,"missing track state fails closed")
local missingWeightTarget=SEGCFG.deepCopyEssential(rawSegment)
missingWeightTarget.samples[1].temporalPoseTelemetry.cameraModuleBefore.animation.tracks[1].weightTarget=nil
expectInvalidSegment(missingWeightTarget,"missing target weight fails closed")
local duplicateEnding=SEGCFG.deepCopyEssential(rawSegment)
local duplicateTrack=SEGCFG.deepCopyEssential(duplicateEnding.samples[1].temporalPoseTelemetry.cameraModuleAfter.animation.tracks[1])
table.insert(duplicateEnding.samples[1].temporalPoseTelemetry.cameraModuleAfter.animation.tracks,duplicateTrack)
expectInvalidSegment(duplicateEnding,"duplicate ending identity fails closed")
local malformedEndingPose=SEGCFG.deepCopyEssential(rawSegment)
malformedEndingPose.samples[1].temporalPoseTelemetry.cameraModuleAfter.primaryCFrame[8]=0/0
expectInvalidSegment(malformedEndingPose,"malformed ending pose fails closed")
local missingViewport=SEGCFG.deepCopyEssential(rawSegment)
missingViewport.samples[1].temporalPoseTelemetry.cameraModuleBefore.viewport=nil
expectInvalidSegment(missingViewport,"missing viewport fails closed")
print("PASS: V614 temporal pose feature characterization")
'''
    with tempfile.TemporaryDirectory(prefix="v614-feature-test-") as temp_dir:
        test_path = Path(temp_dir) / "feature_test.luau"
        test_path.write_text(program, encoding="utf-8")
        completed = subprocess.run(
            [str(luau_binary()), str(test_path)], check=False, text=True,
            capture_output=True,
        )
    if completed.returncode != 0:
        details = (completed.stdout + completed.stderr).strip()
        suffix = f": {details}" if details else ""
        fail(f"feature characterization failed{suffix}")
    expected = "PASS: V614 temporal pose feature characterization\n"
    if completed.stdout != expected:
        fail(f"unexpected feature output: {completed.stdout!r}")
    print(completed.stdout, end="")


def run_candidate_characterization(source: str) -> None:
    helpers = extract_essential_helpers(source)
    program = r'''local SEGCFG={}
''' + helpers + r'''

local function expect(condition,message)
    if not condition then error(message,0) end
end

local profiles=SEGCFG.controlledProfiles()
local identity={0,0,0,1,0,0,0,1,0,0,0,1}
local function feature(id)
    return {
        id=id,totalSignedYaw=60,totalAbsYaw=60,netPitch=0,totalAbsPitch=1,
        duration=0.100,frameCount=10,animationAdvance=0.100,
        initialLocalHead={0,0,0,1,0,0,0,1,0,0,0,1},cameraToPrimary=identity,
        initialHeadDepth=10,fieldOfView=70,viewport={828,1792},humanoidState="Running",
        dominantTrack={key="rbxassetid://idle|Idle|Core|true|2",length=2,looped=true,
            timePosition=0,speed=1,weightCurrent=0.6},
    }
end
local validTouch=feature("touch-1")
local validRelay=feature("relay-1")
local function copy(value) return SEGCFG.deepCopyEssential(value) end
local function expectCandidate(touch,relay,profile)
    local candidate,reason=SEGCFG.controlledCandidate(touch,relay,profile)
    expect(candidate~=nil,"expected candidate: "..tostring(reason))
    expect(reason==nil,"candidate reason")
    return candidate
end
local function expectRejected(relay,reason)
    local candidate,actual=SEGCFG.controlledCandidate(validTouch,relay,profiles.Moderate)
    expect(candidate==nil,"unexpected candidate for "..reason)
    expect(actual==reason,"expected "..reason..", got "..tostring(actual))
end
local function withGap(field,value)
    local relay=copy(validRelay)
    if field=="duration" then relay.duration=validTouch.duration+value
    elseif field=="frameCount" then relay.frameCount=validTouch.frameCount+value
    elseif field=="animationAdvance" then relay.animationAdvance=validTouch.animationAdvance+value
    elseif field=="localHeadTranslation" then relay.initialLocalHead[1]=value
    elseif field=="localHeadRotation" then
        local radians=math.rad(value)
        relay.initialLocalHead[4]=math.cos(radians); relay.initialLocalHead[6]=-math.sin(radians)
        relay.initialLocalHead[10]=math.sin(radians); relay.initialLocalHead[12]=math.cos(radians)
    elseif field=="animationPhaseFraction" then relay.dominantTrack.timePosition=value*relay.dominantTrack.length
    elseif field=="cameraPrimaryRotation" then
        local radians=math.rad(value)
        relay.cameraToPrimary[4]=math.cos(radians); relay.cameraToPrimary[6]=-math.sin(radians)
        relay.cameraToPrimary[10]=math.sin(radians); relay.cameraToPrimary[12]=math.cos(radians)
    elseif field=="initialHeadDepth" then relay.initialHeadDepth=validTouch.initialHeadDepth+value
    else error("unknown gap "..field,0) end
    return relay
end

local candidate=expectCandidate(validTouch,validRelay,profiles.Moderate)
expect(candidate.durationGap==0,"zero duration candidate")
expect(candidate.animationPhaseGap==0,"zero raw animation phase gap")
candidate=expectCandidate(validTouch,withGap("duration",0.067),profiles.Moderate)
expect(candidate.durationGap==0.067,"duration boundary passes")
candidate=expectCandidate(validTouch,withGap("animationPhaseFraction",0.100),profiles.Moderate)
expect(candidate.animationPhaseGap==0.2,"raw animation phase gap is retained in seconds")
expect(candidate.animationPhaseFraction==0.1,"normalized animation phase gap is retained for D")
expectCandidate(validTouch,withGap("frameCount",4),profiles.Moderate)
expectCandidate(validTouch,withGap("animationAdvance",0.067),profiles.Moderate)
expectCandidate(validTouch,withGap("localHeadTranslation",0.050),profiles.Moderate)
expectCandidate(validTouch,withGap("localHeadRotation",2.500),profiles.Moderate)
expectCandidate(validTouch,withGap("animationPhaseFraction",0.100),profiles.Moderate)
expectCandidate(validTouch,withGap("cameraPrimaryRotation",5.000),profiles.Moderate)
expectCandidate(validTouch,withGap("initialHeadDepth",0.050),profiles.Moderate)
expectRejected(withGap("duration",0.067001),"duration-gap")
expectRejected(withGap("frameCount",5),"frame-count-gap")
expectRejected(withGap("animationAdvance",0.067001),"animation-advance-gap")
expectRejected(withGap("localHeadTranslation",0.050001),"local-head-translation-gap")
expectRejected(withGap("localHeadRotation",2.500001),"local-head-rotation-gap")
expectRejected(withGap("animationPhaseFraction",0.100001),"animation-phase-gap")
expectRejected(withGap("cameraPrimaryRotation",5.000001),"camera-primary-rotation-gap")
expectRejected(withGap("initialHeadDepth",0.050001),"initial-head-depth-gap")

local reverse=copy(validRelay); reverse.totalSignedYaw=-60
expectRejected(reverse,"direction")
local yawBoundary=copy(validRelay); yawBoundary.totalAbsYaw=65
expectCandidate(validTouch,yawBoundary,profiles.Moderate)
local yaw=copy(validRelay); yaw.totalAbsYaw=65.000001
expectRejected(yaw,"yaw-gap")
local netPitchBoundary=copy(validRelay); netPitchBoundary.netPitch=1
expectCandidate(validTouch,netPitchBoundary,profiles.Moderate)
local netPitch=copy(validRelay); netPitch.netPitch=1.000001
expectRejected(netPitch,"net-pitch-gap")
local absPitchBoundary=copy(validRelay); absPitchBoundary.totalAbsPitch=3
expectCandidate(validTouch,absPitchBoundary,profiles.Moderate)
local absPitch=copy(validRelay); absPitch.totalAbsPitch=3.000001
expectRejected(absPitch,"abs-pitch-gap")
local fov=copy(validRelay); fov.fieldOfView=71
expectRejected(fov,"camera-config")
local viewport=copy(validRelay); viewport.viewport[2]=1793
expectRejected(viewport,"camera-config")
local track=copy(validRelay); track.dominantTrack.key="other"
expectRejected(track,"animation-identity")
local state=copy(validRelay); state.humanoidState="Jumping"
expectRejected(state,"humanoid-state")
local speed=copy(validRelay); speed.dominantTrack.speed=1.050001
expectRejected(speed,"speed-gap")
local speedBoundary=copy(validRelay); speedBoundary.dominantTrack.speed=1.05
expectCandidate(validTouch,speedBoundary,profiles.Moderate)
local weight=copy(validRelay); weight.dominantTrack.weightCurrent=0.650001
expectRejected(weight,"weight-gap")
local weightBoundary=copy(validRelay); weightBoundary.dominantTrack.weightCurrent=0.65
expectCandidate(validTouch,weightBoundary,profiles.Moderate)
local missing=copy(validRelay); missing.duration=nil
expectRejected(missing,"missing-duration")
local missingViewport=copy(validRelay); missingViewport.viewport=nil
expectRejected(missingViewport,"missing-viewport")

local costGaps={yawGap=2.5,netPitchGap=0.5,absPitchGap=0,durationGap=0,frameCountGap=0,
    animationAdvanceGap=0,localHeadTranslationGap=0,localHeadRotationGap=0,
    animationPhaseGap=99,animationPhaseFraction=0,cameraPrimaryRotationGap=0,initialHeadDepthGap=0}
local integerCost,distance=SEGCFG.controlledIntegerCost(costGaps,profiles.Moderate)
expect(integerCost==500000000000,"two normalized half-gaps yield D squared 0.5")
expect(distance==math.sqrt(0.5),"report distance")
local firstProfiles=SEGCFG.controlledProfiles()
firstProfiles.Moderate.durationGap=99
expect(SEGCFG.controlledProfiles().Moderate.durationGap==0.067,"profiles remain immutable across calls")
local impossible=copy(validRelay); impossible.duration=validTouch.duration+100
local candidates,rejections=SEGCFG.buildControlledCandidates({validTouch},{impossible},profiles.Strict)
expect(#candidates==0 and rejections["duration-gap"]==1,"candidate builder counts fixed rejection")
expect(profiles.Strict.durationGap==0.034,"candidate builder never widens calipers")
print("PASS: V614 controlled candidate gates and scientific cost")
'''
    with tempfile.TemporaryDirectory(prefix="v614-candidate-test-") as temp_dir:
        test_path = Path(temp_dir) / "candidate_test.luau"
        test_path.write_text(program, encoding="utf-8")
        completed = subprocess.run(
            [str(luau_binary()), str(test_path)], check=False, text=True,
            capture_output=True,
        )
    if completed.returncode != 0:
        details = (completed.stdout + completed.stderr).strip()
        suffix = f": {details}" if details else ""
        fail(f"candidate characterization failed{suffix}")
    expected = "PASS: V614 controlled candidate gates and scientific cost\n"
    if completed.stdout != expected:
        fail(f"unexpected candidate output: {completed.stdout!r}")
    print(completed.stdout, end="")


def run_solver_characterization(source: str) -> None:
    helpers = extract_essential_helpers(source)
    program = r'''local SEGCFG={}
''' + helpers + r'''

local function expect(condition,message)
    if not condition then error(message,0) end
end

local function feature(id,endTime)
    return {id=id,endTime=endTime or 0}
end

local function edge(touch,relay,cost)
    return {touch=touch,relay=relay,touchId=touch.id,relayId=relay.id,
        integerCost=cost,distance=math.sqrt(cost)}
end

local function key(candidate)
    return candidate.touchId.."|"..candidate.relayId
end

local function sortedKeys(pairs)
    local keys={}
    for index,pair in ipairs(pairs) do keys[index]=key(pair) end
    table.sort(keys)
    return keys
end

local function expectKeys(pairs,expected,message)
    local actual=sortedKeys(pairs)
    expect(#actual==#expected,message.." count")
    for index,value in ipairs(expected) do
        expect(actual[index]==value,message.." key "..index..": "..tostring(actual[index]))
    end
end

local function reversed(values)
    local output={}
    for index=#values,1,-1 do output[#output+1]=values[index] end
    return output
end

local t1,t2=feature("T1",1),feature("T2",2)
local r1,r2=feature("R1",1),feature("R2",2)
local touch,relay={t1,t2},{r1,r2}

-- A cheapest-edge-first greedy pass takes T1-R1 and strands T2.  Maximum
-- cardinality must win before scientific cost is considered.
local greedyTrap={edge(t1,r1,1),edge(t1,r2,2),edge(t2,r1,2)}
expect(SEGCFG.maximumControlledCardinality(touch,relay,greedyTrap)==2,
    "maximum cardinality defeats greedy")
local greedySolved=SEGCFG.solveControlledMatching(touch,relay,greedyTrap)
expectKeys(greedySolved,{"T1|R2","T2|R1"},"greedy counterexample")

-- Both perfect matchings have cardinality two, so integer scientific cost
-- decides independently of input ordering.
local costEdges={edge(t1,r1,10),edge(t1,r2,1),edge(t2,r1,1),edge(t2,r2,10)}
local minimumCost,minimumEdges=SEGCFG.minimumControlledCost(touch,relay,costEdges,2)
expect(minimumCost==2,"minimum integer scientific cost")
expectKeys(minimumEdges,{"T1|R2","T2|R1"},"minimum cost selection")
expectKeys(SEGCFG.solveControlledMatching(touch,relay,costEdges),
    {"T1|R2","T2|R1"},"minimum cost solver")

-- Equal-cost perfect matchings are resolved by the lexicographically smallest
-- ordered pair-key list, not traversal or caller array order.
local equalCostEdges={edge(t1,r1,1),edge(t1,r2,1),edge(t2,r1,1),edge(t2,r2,1)}
local expected={"T1|R1","T2|R2"}
expectKeys(SEGCFG.solveControlledMatching(touch,relay,equalCostEdges),expected,
    "canonical equal-cost matching")
expectKeys(SEGCFG.solveControlledMatching(reversed(touch),reversed(relay),reversed(equalCostEdges)),
    expected,"canonical reversed-input matching")

local lockedCost,lockedEdges=SEGCFG.minimumControlledCost(touch,relay,equalCostEdges,2,
    {equalCostEdges[2]},{[key(equalCostEdges[1])]=true})
expect(lockedCost==2,"locked edge cost")
expectKeys(lockedEdges,{"T1|R2","T2|R1"},"locked and excluded completion")
expect(SEGCFG.minimumControlledCost(touch,relay,equalCostEdges,3)==nil,
    "infeasible required cardinality")
expect(SEGCFG.minimumControlledCost(touch,relay,equalCostEdges,2,
    {equalCostEdges[1],equalCostEdges[2]})==nil,"conflicting locked edges")

-- Canonical selection happens first; report/bootstrap order is chronological.
local lateTouch,earlyTouch=feature("T1",20),feature("T2",2)
local lateRelay,earlyRelay=feature("R1",10),feature("R2",3)
local chronological=SEGCFG.solveControlledMatching({lateTouch,earlyTouch},{lateRelay,earlyRelay},{
    edge(lateTouch,lateRelay,1),edge(earlyTouch,earlyRelay,1),})
expect(key(chronological[1])=="T2|R2" and key(chronological[2])=="T1|R1",
    "selected pairs are chronological")

-- Independent exhaustive oracle for every 3x3 eligibility graph.  Costs
-- deliberately contain ties.  This catches cardinality, total-cost, canonical
-- tie, and input-order regressions rather than checking one happy path.
local oracleTouch={feature("T1",1),feature("T2",2),feature("T3",3)}
local oracleRelay={feature("R1",1),feature("R2",2),feature("R3",3)}
local allEdges={}
for touchIndex,touchFeature in ipairs(oracleTouch) do
    for relayIndex,relayFeature in ipairs(oracleRelay) do
        allEdges[#allEdges+1]=edge(touchFeature,relayFeature,(touchIndex+relayIndex)%3+1)
    end
end

local function keyListLess(a,b)
    for index=1,math.min(#a,#b) do
        if a[index]~=b[index] then return a[index]<b[index] end
    end
    return #a<#b
end

local function bruteForce(candidates)
    local bestCount,bestCost,bestKeys=-1,nil,nil
    for mask=0,2^#candidates-1 do
        local usedTouch,usedRelay,keys,cost,valid={},{},{},0,true
        for index,candidate in ipairs(candidates) do
            if math.floor(mask/2^(index-1))%2==1 then
                if usedTouch[candidate.touchId] or usedRelay[candidate.relayId] then
                    valid=false; break
                end
                usedTouch[candidate.touchId]=true; usedRelay[candidate.relayId]=true
                keys[#keys+1]=key(candidate); cost+=candidate.integerCost
            end
        end
        if valid then
            table.sort(keys)
            if #keys>bestCount or (#keys==bestCount and (bestCost==nil or cost<bestCost
                or (cost==bestCost and keyListLess(keys,bestKeys)))) then
                bestCount,bestCost,bestKeys=#keys,cost,keys
            end
        end
    end
    return bestCount,bestCost,bestKeys
end

for graphMask=0,2^#allEdges-1 do
    local candidates={}
    for index,candidate in ipairs(allEdges) do
        if math.floor(graphMask/2^(index-1))%2==1 then candidates[#candidates+1]=candidate end
    end
    local wantCount,wantCost,wantKeys=bruteForce(candidates)
    expect(SEGCFG.maximumControlledCardinality(oracleTouch,oracleRelay,candidates)==wantCount,
        "exhaustive cardinality graph "..graphMask)
    local actualCost=SEGCFG.minimumControlledCost(oracleTouch,oracleRelay,candidates,wantCount)
    expect(actualCost==wantCost,"exhaustive cost graph "..graphMask)
    expectKeys(SEGCFG.solveControlledMatching(oracleTouch,oracleRelay,candidates),wantKeys,
        "exhaustive canonical graph "..graphMask)
    expectKeys(SEGCFG.solveControlledMatching(reversed(oracleTouch),reversed(oracleRelay),reversed(candidates)),
        wantKeys,"exhaustive reversed graph "..graphMask)
end

-- Profile integration builds real candidates and returns the complete frozen
-- result contract consumed by Task 5.
local identity={0,0,0,1,0,0,0,1,0,0,0,1}
local function controlledFeature(id,endTime)
    return {
        id=id,endTime=endTime,totalSignedYaw=60,totalAbsYaw=60,netPitch=0,totalAbsPitch=1,
        duration=0.100,frameCount=10,animationAdvance=0.100,
        initialLocalHead=identity,cameraToPrimary=identity,initialHeadDepth=10,
        fieldOfView=70,viewport={828,1792},humanoidState="Running",
        dominantTrack={key="rbxassetid://idle|Idle|Core|true|2",length=2,looped=true,
            timePosition=0,speed=1,weightCurrent=0.6},
    }
end
local profileResult=SEGCFG.runControlledProfile({
    touch={controlledFeature("T1",1),controlledFeature("T2",2)},
    relay={controlledFeature("R1",1),controlledFeature("R2",2)},
},SEGCFG.controlledProfiles().Moderate)
expect(#profileResult.candidates==4,"profile candidate list")
expect(profileResult.cardinality==2 and #profileResult.pairs==2,"profile cardinality")
expect(profileResult.totalCost==0,"profile total cost")
expect(next(profileResult.rejectionCounts)==nil,"profile rejection counts")
expectKeys(profileResult.pairs,expected,"profile canonical pairs")

print("PASS: V614 deterministic maximum-cardinality minimum-cost solver")
'''
    with tempfile.TemporaryDirectory(prefix="v614-solver-test-") as temp_dir:
        test_path = Path(temp_dir) / "solver_test.luau"
        test_path.write_text(program, encoding="utf-8")
        completed = subprocess.run(
            [str(luau_binary()), str(test_path)], check=False, text=True,
            capture_output=True,
        )
    if completed.returncode != 0:
        details = (completed.stdout + completed.stderr).strip()
        suffix = f": {details}" if details else ""
        fail(f"solver characterization failed{suffix}")
    expected_output = (
        "PASS: V614 deterministic maximum-cardinality minimum-cost solver\n"
    )
    if completed.stdout != expected_output:
        fail(f"unexpected solver output: {completed.stdout!r}")
    print(completed.stdout, end="")


def run_retention_characterization(source: str) -> None:
    stop_start = source.find("local function stopProbe()")
    stop_end = source.find("\nlocal function baseSafe()", stop_start)
    if stop_start < 0 or stop_end < 0:
        fail("stopProbe source anchors are missing")
    stop_source = source[stop_start:stop_end]
    ordered_calls = (
        'SEGCFG.closeCurrentSegment("probe-stop")',
        "SEGCFG.prepareControlledMatching()",
        "SEGCFG.pruneTelemetryToAnalysisUnion(controlled)",
        "probeRunning=false",
    )
    positions = [stop_source.find(call) for call in ordered_calls]
    if any(position < 0 for position in positions) or positions != sorted(positions):
        fail("stopProbe does not freeze and union-prune in the required order")
    if "SEGCFG.pruneTelemetryToMatched()" in stop_source:
        fail("stopProbe still performs baseline-only telemetry pruning")

    helpers = extract_essential_helpers(source)
    matcher = extract_section(source, "matchSegments")
    preparation = extract_controlled_preparation(source)
    program = r'''local SEGCFG={
    matchYawGap=5.0,matchNetPitchGap=1.0,matchAbsPitchGap=2.0,
    controlledResults=nil,controlledPreparationErrors={},
}
local segmentStats={touch={eligible={}},relay={eligible={}}}
''' + helpers + "\n" + matcher + "\n" + preparation + r'''

local function expect(condition,message)
    if not condition then error(message,0) end
end

local identity={0,0,0,1,0,0,0,1,0,0,0,1}
local camera={0,0,0,1,0,0,0,1,0,0,0,1}
local head={0,0,-10,1,0,0,0,1,0,0,0,1}
local function snapshot(timePosition)
    return {fieldOfView=70,viewport={828,1792},cameraCFrame=camera,
        primaryCFrame=identity,headCFrame=head,primaryToHead=identity,
        animation={humanoidState="Running",tracks={{animationId="rbxassetid://idle",name="Idle",
            priority="Core",looped=true,length=2,timePosition=timePosition,speed=1,
            weightCurrent=0.6,weightTarget=0.6,isPlaying=true}}}}
end
local function rawSegment(id,route,endTime)
    return {id=id,route=route,window=route=="touch" and "A1" or "B1",
        startTime=endTime-0.1,endTime=endTime,duration=0.1,frameCount=6,
        totalSignedYaw=60,totalAbsYaw=60,netPitch=0,totalAbsPitch=1,
        head={x=101},primary={x=100},subject={x=99},samples={{temporalPoseTelemetry={
            cameraModuleBefore=snapshot(0.1),cameraModuleAfter=snapshot(0.2),controllerCalls={}}}}}
end
local function resetControlled()
    SEGCFG.controlledResults=nil
    SEGCFG.controlledPreparationErrors={}
end

-- Both route arrays must be copied before baseline matching.  Mutating the
-- live arrays inside the baseline call cannot redirect feature extraction.
local realMatcher=SEGCFG.matchSegments
local realExtractor=SEGCFG.controlledFeatureFromRawSegment
local realProfiles=SEGCFG.controlledProfiles
local realProfileRunner=SEGCFG.runControlledProfile
local originalTouch=rawSegment("touch-original","touch",1)
local originalRelay=rawSegment("relay-original","relay",2)
segmentStats.touch.eligible={originalTouch}
segmentStats.relay.eligible={originalRelay}
local baselineCalls=0
SEGCFG.matchSegments=function()
    baselineCalls+=1
    segmentStats.touch.eligible={rawSegment("touch-mutated","touch",3)}
    segmentStats.relay.eligible={rawSegment("relay-mutated","relay",4)}
    return {}
end
resetControlled()
local frozen=SEGCFG.prepareControlledMatching()
expect(frozen~=nil,"snapshot preparation succeeds")
expect(frozen.features.touch[1].id=="touch-original","Touch features use pre-baseline snapshot")
expect(frozen.features.relay[1].id=="relay-original","relay features use pre-baseline snapshot")
expect(frozen.features.touch[1].segmentRef==originalTouch,"Touch snapshot keeps original reference")
expect(frozen.features.relay[1].segmentRef==originalRelay,"relay snapshot keeps original reference")
expect(frozen.profiles.Strict~=frozen.profiles.Moderate
    and frozen.profiles.Moderate~=frozen.profiles.Broad,"profiles are independent results")
expect(SEGCFG.getFrozenMatchingResults()==frozen,"frozen result getter")
expect(SEGCFG.prepareControlledMatching()==frozen and baselineCalls==1,"preparation is cached")

-- A sparse eligible list is a structural snapshot failure.  Both snapshots
-- are attempted, but no baseline, extractor, or profile code may run.
local sparseTouchA=rawSegment("touch-sparse-a","touch",1)
local sparseTouchB=rawSegment("touch-sparse-b","touch",3)
segmentStats.touch.eligible={[1]=sparseTouchA,[3]=sparseTouchB}
segmentStats.relay.eligible={rawSegment("relay-sparse","relay",2)}
local sparseBaselineCalls,sparseExtractorCalls,sparseProfileCalls=0,0,0
SEGCFG.matchSegments=function() sparseBaselineCalls+=1; return {} end
SEGCFG.controlledFeatureFromRawSegment=function(segment)
    sparseExtractorCalls+=1
    return realExtractor(segment)
end
SEGCFG.controlledProfiles=function() sparseProfileCalls+=1; return realProfiles() end
resetControlled()
local sparseFailed=SEGCFG.prepareControlledMatching()
expect(sparseFailed==nil and SEGCFG.controlledResults==nil,"sparse eligible list fails closed")
expect(sparseBaselineCalls==0,"sparse structural snapshot stops before baseline")
expect(sparseExtractorCalls==0 and sparseProfileCalls==0,
    "sparse structural snapshot stops before extractor and profiles")
expect(#SEGCFG.controlledPreparationErrors==1
    and SEGCFG.controlledPreparationErrors[1].stage=="snapshot"
    and SEGCFG.controlledPreparationErrors[1].code=="eligible-list-invalid"
    and SEGCFG.controlledPreparationErrors[1].route=="touch"
    and SEGCFG.controlledPreparationErrors[1].reason=="sparse-list"
    and SEGCFG.controlledPreparationErrors[1].index==2,
    "sparse eligible list audit is deterministic")
SEGCFG.matchSegments=realMatcher
SEGCFG.controlledFeatureFromRawSegment=realExtractor
SEGCFG.controlledProfiles=realProfiles

-- A non-table entry is passed to the real, unchanged matcher.  Its real
-- failure is caught, audited deterministically, and leaves no partial result.
local malformedTouch=rawSegment("touch-valid","touch",1)
local malformedRelay=rawSegment("relay-valid","relay",2)
segmentStats.touch.eligible={malformedTouch,"not-a-segment"}
segmentStats.relay.eligible={malformedRelay}
resetControlled()
local failed=SEGCFG.prepareControlledMatching()
expect(failed==nil and SEGCFG.controlledResults==nil,"real baseline failure is fail-closed")
expect(#SEGCFG.controlledPreparationErrors==2,"malformed input and baseline error are audited once")
expect(SEGCFG.controlledPreparationErrors[1].stage=="snapshot"
    and SEGCFG.controlledPreparationErrors[1].code=="non-table-segment"
    and SEGCFG.controlledPreparationErrors[1].route=="touch"
    and SEGCFG.controlledPreparationErrors[1].index==2,"malformed segment audit is deterministic")
expect(SEGCFG.controlledPreparationErrors[2].stage=="baseline"
    and SEGCFG.controlledPreparationErrors[2].code=="baseline-error","real matcher error is audited")
local failedAgain=SEGCFG.prepareControlledMatching()
expect(failedAgain==nil and #SEGCFG.controlledPreparationErrors==2,
    "failed preparation retries without accumulating audit noise")
local failClosedSummary=SEGCFG.pruneTelemetryToAnalysisUnion(failedAgain)
expect(failClosedSummary.skipped==true,"failed preparation never prunes telemetry")
expect(malformedTouch.samples[1].temporalPoseTelemetry~=nil
    and malformedRelay.samples[1].temporalPoseTelemetry~=nil,"failed preparation retains telemetry")

-- A baseline exception with structurally valid eligible lists is audited and
-- cannot promote a partial frozen result.
segmentStats.touch.eligible={rawSegment("touch-baseline-error","touch",1)}
segmentStats.relay.eligible={rawSegment("relay-baseline-error","relay",2)}
SEGCFG.matchSegments=function() error("forced baseline failure",0) end
resetControlled()
local baselineFailed=SEGCFG.prepareControlledMatching()
expect(baselineFailed==nil and SEGCFG.controlledResults==nil,"baseline exception is fail-closed")
expect(#SEGCFG.controlledPreparationErrors==1
    and SEGCFG.controlledPreparationErrors[1].stage=="baseline"
    and SEGCFG.controlledPreparationErrors[1].code=="baseline-error"
    and string.find(SEGCFG.controlledPreparationErrors[1].reason,"forced baseline failure",1,true)~=nil,
    "baseline exception audit")
SEGCFG.matchSegments=realMatcher

-- Extractor exceptions remain structural failures. Ordinary extractor
-- rejections instead retain a compact ineligible feature and counted reason.
local extractorTouch=rawSegment("touch-extractor","touch",1)
local extractorRelay=rawSegment("relay-extractor","relay",2)
segmentStats.touch.eligible={extractorTouch}
segmentStats.relay.eligible={extractorRelay}
SEGCFG.controlledFeatureFromRawSegment=function(segment)
    if segment==extractorTouch then error("forced extractor failure",0) end
    return realExtractor(segment)
end
resetControlled()
local extractorFailed=SEGCFG.prepareControlledMatching()
expect(extractorFailed==nil and SEGCFG.controlledResults==nil,"extractor exception is fail-closed")
expect(#SEGCFG.controlledPreparationErrors==1
    and SEGCFG.controlledPreparationErrors[1].stage=="feature"
    and SEGCFG.controlledPreparationErrors[1].code=="extractor-error"
    and SEGCFG.controlledPreparationErrors[1].segmentId=="touch-extractor",
    "extractor exception audit")
SEGCFG.controlledFeatureFromRawSegment=realExtractor

local rejectedTouch=rawSegment("touch-rejected","touch",1)
rejectedTouch.duration=nil
segmentStats.touch.eligible={rejectedTouch}
segmentStats.relay.eligible={rawSegment("relay-rejected","relay",2)}
resetControlled()
local rejected=SEGCFG.prepareControlledMatching()
expect(rejected~=nil and #rejected.baseline==1,"ordinary rejection preserves baseline")
expect(#SEGCFG.controlledPreparationErrors==0,"ordinary rejection is not structural failure")
expect(#rejected.features.touch==1 and rejected.features.touch[1].valid==false
    and rejected.features.touch[1].invalidReason=="missing segment duration",
    "invalid feature retains explicit marker and reason")
for _,name in ipairs({"Strict","Moderate","Broad"}) do
    expect(#rejected.profiles[name].pairs==0
        and rejected.profiles[name].rejectionCounts["missing segment duration"]==1,
        name.." counts ordinary feature rejection")
end
segmentStats.touch.eligible[2]=rawSegment("touch-valid-after-rejection","touch",3)
segmentStats.relay.eligible[2]=rawSegment("relay-valid-after-rejection","relay",4)
resetControlled()
local mixedFeatures=SEGCFG.prepareControlledMatching()
expect(#mixedFeatures.baseline==2 and #mixedFeatures.features.touch==2,
    "mixed feature validity preserves the baseline and eligible universe")
for _,name in ipairs({"Strict","Moderate","Broad"}) do
    expect(#mixedFeatures.profiles[name].pairs==1
        and mixedFeatures.profiles[name].pairs[1].touch.id=="touch-valid-after-rejection"
        and mixedFeatures.profiles[name].rejectionCounts["missing segment duration"]==2,
        name.." rejects only invalid-feature candidates and matches valid ones")
end
local mixedRetention=SEGCFG.pruneTelemetryToAnalysisUnion(mixedFeatures)
expect(mixedRetention.skipped==false and rejectedTouch.samples[1].temporalPoseTelemetry~=nil,
    "baseline retains telemetry for an invalid controlled feature")

-- Frozen baseline/profile list fields must be dense and contain real pair or
-- candidate records.  Otherwise pruning could silently omit a retained route.
local shapeTouch=rawSegment("touch-shape","touch",1)
local shapeRelay=rawSegment("relay-shape","relay",2)
segmentStats.touch.eligible={shapeTouch}
segmentStats.relay.eligible={shapeRelay}
local function validFrozenEdge(features)
    return {touch=features.touch[1],relay=features.relay[1],integerCost=0}
end
local function validProfileResult(features)
    local edge=validFrozenEdge(features)
    return {pairs={edge},candidates={edge},rejectionCounts={},cardinality=1,totalCost=0}
end
local function expectInvalidProfileResult(field,value,reason)
    local profileCalls=0
    SEGCFG.runControlledProfile=function(features,profile)
        profileCalls+=1
        local result=validProfileResult(features)
        if profile.durationGap==0.034 then result[field]=value(result) end
        return result
    end
    resetControlled()
    local invalid=SEGCFG.prepareControlledMatching()
    expect(invalid==nil and SEGCFG.controlledResults==nil,"invalid "..field.." fails closed")
    expect(profileCalls==3,"all controlled profiles run independently after a profile result error")
    local found=false
    for _,entry in ipairs(SEGCFG.controlledPreparationErrors) do
        if entry.stage=="profile" and entry.profile=="Strict" and entry.field==field
            and entry.reason==reason then found=true end
    end
    expect(found,"invalid "..field.." audit includes its structural reason")
end
expectInvalidProfileResult("pairs",function(result)
    return {[1]=result.pairs[1],[3]=result.pairs[1]}
end,"sparse-list")
expectInvalidProfileResult("candidates",function(result)
    return {[1]=result.candidates[1],[3]=result.candidates[1]}
end,"sparse-list")
expectInvalidProfileResult("pairs",function() return {"not-a-pair"} end,"invalid-element")
expectInvalidProfileResult("candidates",function() return {false} end,"invalid-element")
SEGCFG.runControlledProfile=realProfileRunner

SEGCFG.matchSegments=function()
    return {[1]={touch=shapeTouch,relay=shapeRelay},[3]={touch=shapeTouch,relay=shapeRelay}}
end
local baselineExtractorCalls=0
SEGCFG.controlledFeatureFromRawSegment=function(segment)
    baselineExtractorCalls+=1
    return realExtractor(segment)
end
resetControlled()
local sparseBaseline=SEGCFG.prepareControlledMatching()
expect(sparseBaseline==nil and SEGCFG.controlledResults==nil,"sparse baseline pairs fail closed")
expect(baselineExtractorCalls==0,"sparse baseline pairs stop before feature extraction")
expect(#SEGCFG.controlledPreparationErrors==1
    and SEGCFG.controlledPreparationErrors[1].stage=="baseline"
    and SEGCFG.controlledPreparationErrors[1].code=="baseline-result-invalid"
    and SEGCFG.controlledPreparationErrors[1].reason=="sparse-list",
    "sparse baseline pairs audit")
SEGCFG.matchSegments=realMatcher
SEGCFG.controlledFeatureFromRawSegment=realExtractor

-- Union retention includes baseline-only, shared Strict/Moderate, and
-- Broad-only segments exactly once, while unmatched telemetry is removed.
local function retentionSegment(id,route)
    return {id=id,route=route,scalar="preserved",samples={{temporalPoseTelemetry={id=id}}}}
end
local baselineTouch,baselineRelay=retentionSegment("baseline-touch","touch"),retentionSegment("baseline-relay","relay")
local sharedTouch,sharedRelay=retentionSegment("shared-touch","touch"),retentionSegment("shared-relay","relay")
local broadTouch,broadRelay=retentionSegment("broad-touch","touch"),retentionSegment("broad-relay","relay")
local unmatchedTouch,unmatchedRelay=retentionSegment("unmatched-touch","touch"),retentionSegment("unmatched-relay","relay")
segmentStats.touch.eligible={baselineTouch,sharedTouch,broadTouch,unmatchedTouch}
segmentStats.relay.eligible={baselineRelay,sharedRelay,broadRelay,unmatchedRelay}
local sharedPair={touch={segmentRef=sharedTouch},relay={segmentRef=sharedRelay}}
local retentionResult={baseline={{touch=baselineTouch,relay=baselineRelay}},profiles={
    Strict={pairs={sharedPair}},Moderate={pairs={sharedPair}},
    Broad={pairs={{touch={segmentRef=broadTouch},relay={segmentRef=broadRelay}}}},}}
local summary=SEGCFG.pruneTelemetryToAnalysisUnion(retentionResult)
expect(summary.skipped==false and summary.retainedSegments==6 and summary.prunedSegments==2,
    "retention summary deduplicates the union")
expect(summary.retainedTelemetrySamples==6 and summary.prunedTelemetrySamples==2,
    "retention sample summary")
for _,segment in ipairs({baselineTouch,baselineRelay,sharedTouch,sharedRelay,broadTouch,broadRelay}) do
    expect(segment.samples[1].temporalPoseTelemetry~=nil,"union telemetry retained for "..segment.id)
end
for _,segment in ipairs({unmatchedTouch,unmatchedRelay}) do
    expect(segment.samples[1].temporalPoseTelemetry==nil,"unmatched telemetry pruned for "..segment.id)
    expect(segment.scalar=="preserved","scalar segment data retained for "..segment.id)
end

-- Sparse or invalid frozen pair lists cannot authorize partial pruning.
local function expectRetentionSkipped(result,message)
    unmatchedTouch.samples[1].temporalPoseTelemetry={id="unmatched-touch"}
    unmatchedRelay.samples[1].temporalPoseTelemetry={id="unmatched-relay"}
    local skipped=SEGCFG.pruneTelemetryToAnalysisUnion(result)
    expect(skipped.skipped==true,message)
    expect(unmatchedTouch.samples[1].temporalPoseTelemetry~=nil
        and unmatchedRelay.samples[1].temporalPoseTelemetry~=nil,
        message.." retains telemetry")
end
local sparseBaselineResult={baseline={
    [1]={touch=baselineTouch,relay=baselineRelay},
    [3]={touch=baselineTouch,relay=baselineRelay},
},profiles=retentionResult.profiles}
expectRetentionSkipped(sparseBaselineResult,"sparse baseline retention list fails closed")
local sparseProfileResult={baseline=retentionResult.baseline,profiles={
    Strict={pairs={[1]=sharedPair,[3]=sharedPair}},
    Moderate=retentionResult.profiles.Moderate,Broad=retentionResult.profiles.Broad,
}}
expectRetentionSkipped(sparseProfileResult,"sparse profile retention list fails closed")
local invalidPairResult={baseline=retentionResult.baseline,profiles={
    Strict={pairs={"not-a-pair"}},
    Moderate=retentionResult.profiles.Moderate,Broad=retentionResult.profiles.Broad,
}}
expectRetentionSkipped(invalidPairResult,"invalid profile pair fails closed")

-- Both live eligible lists must be validated before either route is pruned.
-- A malformed relay container cannot erase already-visited Touch telemetry.
local atomicResult={baseline={},profiles={
    Strict={pairs={}},Moderate={pairs={}},Broad={pairs={}},
}}
local atomicTouch=retentionSegment("atomic-touch","touch")
segmentStats.touch.eligible={atomicTouch}
segmentStats.relay.eligible="malformed"
local nonTableEligible=SEGCFG.pruneTelemetryToAnalysisUnion(atomicResult)
expect(nonTableEligible.skipped==true,"non-table relay eligible list skips pruning")
expect(atomicTouch.samples[1].temporalPoseTelemetry~=nil,
    "non-table relay eligible list preserves Touch telemetry atomically")
expect(type(nonTableEligible.reason)=="string"
    and string.find(nonTableEligible.reason,"relay",1,true)~=nil,
    "non-table relay eligible reason identifies the route")

-- A sparse relay list is also rejected before any telemetry mutation, and
-- every reachable segment on both routes remains intact.
local sparseLiveTouch=retentionSegment("sparse-live-touch","touch")
local sparseLiveRelayA=retentionSegment("sparse-live-relay-a","relay")
local sparseLiveRelayB=retentionSegment("sparse-live-relay-b","relay")
segmentStats.touch.eligible={sparseLiveTouch}
segmentStats.relay.eligible={[1]=sparseLiveRelayA,[3]=sparseLiveRelayB}
local sparseLiveEligible=SEGCFG.pruneTelemetryToAnalysisUnion(atomicResult)
expect(sparseLiveEligible.skipped==true,"sparse relay eligible list skips pruning")
expect(type(sparseLiveEligible.reason)=="string"
    and string.find(sparseLiveEligible.reason,"relay",1,true)~=nil
    and string.find(sparseLiveEligible.reason,"sparse-list",1,true)~=nil,
    "sparse relay eligible reason identifies route and shape")
for _,segment in ipairs({sparseLiveTouch,sparseLiveRelayA,sparseLiveRelayB}) do
    expect(segment.samples[1].temporalPoseTelemetry~=nil,
        "sparse relay eligible list preserves telemetry for "..segment.id)
end

print("PASS: V614 pre-prune freeze and telemetry union retention")
'''
    with tempfile.TemporaryDirectory(prefix="v614-retention-test-") as temp_dir:
        test_path = Path(temp_dir) / "retention_test.luau"
        test_path.write_text(program, encoding="utf-8")
        completed = subprocess.run(
            [str(luau_binary()), str(test_path)], check=False, text=True,
            capture_output=True,
        )
    if completed.returncode != 0:
        details = (completed.stdout + completed.stderr).strip()
        suffix = f": {details}" if details else ""
        fail(f"retention characterization failed{suffix}")
    expected = "PASS: V614 pre-prune freeze and telemetry union retention\n"
    if completed.stdout != expected:
        fail(f"unexpected retention output: {completed.stdout!r}")
    print(completed.stdout, end="")


def run_decision_characterization(source: str) -> None:
    helpers = extract_essential_helpers(source)
    program = r'''local SEGCFG={}
''' + helpers + r'''

local function expect(condition,message)
    if not condition then error(message,0) end
end

local function ci(estimate,low,high,excludesZero)
    return {n=12,estimate=estimate,low=low,high=high,excludesZero=excludesZero}
end

local function fakeAnalysis(pairCount,headCI,decomposition)
    return {
        pairCount=pairCount,
        pairs={},
        bootstrap={
            headHorizontal=headCI,
            headDecomposition=decomposition or {
                endpoint=ci(-0.001,-0.01,0.01,false),
                within=ci(-0.001,-0.01,0.01,false),
                between=ci(-0.001,-0.01,0.01,false),
            },
        },
    }
end

local function decisionFor(moderate,parityEqual)
    return SEGCFG.controlledDecision({
        profiles={
            Strict=fakeAnalysis(12,ci(-0.001,-0.01,0.01,false)),
            Moderate=moderate,
            Broad=fakeAnalysis(12,ci(-0.001,-0.01,0.01,false)),
        },
        parity={equal=parityEqual},
    },12)
end

local insufficient=fakeAnalysis(11,ci(-0.01,-0.02,-0.005,true))
local disappears=fakeAnalysis(12,ci(-0.001,-0.01,0.01,false))
local persists=fakeAnalysis(12,ci(-0.01,-0.02,-0.005,true),{
    endpoint=ci(-0.001,-0.01,0.01,false),
    within=ci(-0.01,-0.02,-0.005,true),
    between=ci(-0.001,-0.01,0.01,false),
})
local insufficientDecision=decisionFor(insufficient,true)
local parityFailedDecision=decisionFor(persists,false)
local disappearsDecision=decisionFor(disappears,true)
local persistsDecision=decisionFor(persists,true)
local mismatchedBootstrap=fakeAnalysis(12,ci(-0.01,-0.02,-0.005,true))
mismatchedBootstrap.bootstrap.headHorizontal.n=13
local mismatchedBootstrapDecision=decisionFor(mismatchedBootstrap,true)

expect(insufficientDecision.temporalConfoundResolved=="unproved: insufficient controlled overlap","n<12 temporal")
expect(insufficientDecision.initialPoseConfoundResolved=="unproved: insufficient controlled overlap","n<12 pose")
expect(insufficientDecision.causalMechanismProved==false,"n<12 mechanism blocked")
expect(insufficientDecision.implementationTargetIdentified==false,"n<12 target blocked")
expect(insufficientDecision.v615Justified==false,"n<12 V615 blocked")
expect(insufficientDecision.astra6MaxJustified==false,"n<12 Astra blocked")
expect(insufficientDecision.pcEquivalenceClaimAllowed==false,"n<12 PC equivalence blocked")
expect(parityFailedDecision.temporalConfoundResolved=="unproved: insufficient controlled overlap","parity temporal")
expect(parityFailedDecision.headHorizontalEffectAfterTemporalControl=="unproved","parity effect")
expect(mismatchedBootstrapDecision.temporalConfoundResolved
    =="unproved: insufficient controlled overlap","bootstrap n must equal pair count")
expect(disappearsDecision.headHorizontalEffectAfterTemporalControl=="not-supported","CI includes zero")
expect(disappearsDecision.temporalConfoundResolved==true and disappearsDecision.initialPoseConfoundResolved==true,
    "adequate controlled overlap resolves measured confounds")
expect(persistsDecision.headHorizontalEffectAfterTemporalControl=="persists-under-fixed-controls","CI excludes zero")
expect(persistsDecision.firstConcreteGeometricDivergence=="Head within-update","first excluding component")
expect(persistsDecision.causalMechanismProved==false,"persistence alone is not mechanism")
expect(persistsDecision.implementationTargetIdentified==false,"decomposition is not implementation target")
expect(persistsDecision.v615Justified==false and persistsDecision.astra6MaxJustified==false,"no automatic promotion")
expect(string.find(persistsDecision.qualitativeOnlyEmergencyModeClue,"qualitative-only:",1,true)==1,
    "emergency clue stays explicitly qualitative-only")

local unresolved=fakeAnalysis(12,ci(-0.01,-0.02,-0.005,true))
local unresolvedDecision=decisionFor(unresolved,true)
expect(unresolvedDecision.firstConcreteGeometricDivergence
    =="unproved: persistent endpoint effect not isolated by decomposition","decomposition remains unproved")
print("PASS: V614 Moderate-primary controlled decisions fail closed")
'''
    with tempfile.TemporaryDirectory(prefix="v614-decision-test-") as temp_dir:
        test_path = Path(temp_dir) / "decision_test.luau"
        test_path.write_text(program, encoding="utf-8")
        completed = subprocess.run(
            [str(luau_binary()), str(test_path)], check=False, text=True,
            capture_output=True,
        )
    if completed.returncode != 0:
        details = (completed.stdout + completed.stderr).strip()
        suffix = f": {details}" if details else ""
        fail(f"decision characterization failed{suffix}")
    expected = "PASS: V614 Moderate-primary controlled decisions fail closed\n"
    if completed.stdout != expected:
        fail(f"unexpected decision output: {completed.stdout!r}")
    print(completed.stdout, end="")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--baseline-only",
        action="store_true",
        help="run only the V614 baseline/acquisition guard rails",
    )
    parser.add_argument(
        "--features",
        action="store_true",
        help="run pure temporal-pose feature characterization",
    )
    parser.add_argument(
        "--candidates",
        action="store_true",
        help="run fixed controlled-candidate gate and cost characterization",
    )
    parser.add_argument(
        "--solver",
        action="store_true",
        help="run deterministic optimal controlled-matching characterization",
    )
    parser.add_argument(
        "--retention",
        action="store_true",
        help="run pre-prune freezing and telemetry-union characterization",
    )
    parser.add_argument(
        "--decisions",
        action="store_true",
        help="run Moderate-primary controlled decision characterization",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="run every V614 temporal-pose characterization",
    )
    args = parser.parse_args()
    if not args.baseline_only and not args.features and not args.candidates \
            and not args.solver and not args.retention and not args.decisions \
            and not args.all:
        parser.error(
            "select --decisions, --retention, --solver, --candidates, --features, or --baseline-only"
        )

    try:
        source = RUNTIME.read_text(encoding="utf-8")
        check_source_invariants(source)
        if args.features or args.all:
            run_feature_characterization(source)
        if args.candidates or args.all:
            run_candidate_characterization(source)
        if args.solver or args.all:
            run_solver_characterization(source)
        if args.retention or args.all:
            run_retention_characterization(source)
        if args.decisions or args.all:
            run_decision_characterization(source)
        if args.baseline_only or args.all:
            print("PASS: V614 protected baseline/acquisition source is unchanged")
            run_matcher_characterization(source)
            check_protected_files()
            print("PASS: V20/V500/V604 hashes are byte-identical")
    except (InvariantFailure, OSError, UnicodeError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
