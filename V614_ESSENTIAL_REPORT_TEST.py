#!/usr/bin/env python3
"""Execute V614 R2 essential-report helpers against deterministic telemetry."""

from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "PCMovementV614_ControlledYawPitchMatching.lua"
LOADER = ROOT / "Loader.lua"
START = "-- BEGIN V614 ESSENTIAL REPORT PURE HELPERS"
END = "-- END V614 ESSENTIAL REPORT PURE HELPERS"


def luau_binary() -> Path:
    configured = os.environ.get("LUAU_BIN")
    return Path(configured) if configured else ROOT.parent / "tooling" / "luau-bin" / "luau"


source = RUNTIME.read_text(encoding="utf-8")
loader_source = LOADER.read_text(encoding="utf-8")
match = re.search(re.escape(START) + r"\n(.*?)\n" + re.escape(END), source, re.S)
if not match:
    raise SystemExit("RED: production V614 essential-report helper block is missing")
report_match = re.search(
    r"(local function essentialJsonValue\(value\).*?)\ngetgenv\(\)\.PCV614EssentialReport=function\(\)",
    source,
    re.S,
)
if not report_match:
    raise SystemExit("RED: production V614 controlled report builder is missing")

if "getgenv().PCV614EssentialReport=function()" not in source:
    raise SystemExit("RED: PCV614EssentialReport entry point is missing")
if "local fullReport=getgenv().PCV614EssentialReport()" not in source:
    raise SystemExit("RED: chunk export is not wired to the essential report")
if 'local revision="V614-ControlledAcquisitionR3-TemporalPoseControlR2-FullClipboardR1"' not in loader_source:
    raise SystemExit("RED: Loader essential-report cache revision is missing")

REPORT_SECTIONS = (
    "=== V614 BASELINE MATCHER (UNCHANGED) ===",
    "=== V614 CONTROLLED STRICT ===",
    "=== V614 CONTROLLED MODERATE (PRIMARY) ===",
    "=== V614 CONTROLLED BROAD ===",
    "=== V614 CONTROLLED SENSITIVITY SUMMARY ===",
    "=== V614 TEMPORAL + INITIAL-POSE DECISION ===",
)
section_positions = [source.find(section) for section in REPORT_SECTIONS]
if any(position < 0 for position in section_positions):
    missing = [section for section, position in zip(REPORT_SECTIONS, section_positions) if position < 0]
    raise SystemExit("RED: controlled report sections are missing: " + " | ".join(missing))
if section_positions != sorted(section_positions):
    raise SystemExit("RED: controlled report sections are out of order")
for literal in (
    "publishedBaselineHeadEffectStatus",
    "controlledGapDistributions",
    "controlledHorizontalResults",
    "controlledRouteDistributions",
    "controlledInitialPoseDistributions",
    "controlledPairDecomposition",
    "controlledRejectionCounts",
    "controlledCoverage",
    "controlledCandidateCount",
    "controlledPairIdentity",
    "qualitativeOnlyEmergencyModeClue",
):
    if literal not in source:
        raise SystemExit(f"RED: controlled report field is missing: {literal}")


from V614_TEMPORAL_POSE_CONTROL_TEST import extract_section, extract_controlled_preparation

bundle_source = source[source.index("function SEGCFG.buildProductionEssentialBundle()"):
                       source.index("\nlocal function essentialJsonValue")]
entry_source = source[source.index("getgenv().PCV614EssentialReport=function()"):
                      source.index("\ngetgenv().PCV614Report=function()")]
transport_source = source.split("-- BEGIN V614 REPORT TRANSPORT PURE HELPERS\n", 1)[1].split(
    "-- END V614 REPORT TRANSPORT PURE HELPERS", 1)[0]

program = (
    "local SEGCFG={minMatched=12,matchYawGap=5,matchNetPitchGap=1,matchAbsPitchGap=2,reportPayloadMaxChars=29500}\n"
    "local segmentStats={touch={eligible={}},relay={eligible={}}}\n"
    "local environment={}\nlocal function getgenv() return environment end\n"
    "local HttpService={}\n"
    "function HttpService:JSONEncode(value) return '{}' end\n"
    + match.group(1)
    + "\n"
    + report_match.group(1)
    + "\n" + extract_section(source, "matchSegments")
    + "\n" + extract_controlled_preparation(source)
    + "\n" + bundle_source + "\n" + entry_source + "\n" + transport_source
    + r'''
local function expect(condition,message)
    if not condition then error(message,0) end
end

local function countKeys(value)
    local count=0
    for _ in pairs(value or {}) do count+=1 end
    return count
end

local function cf(x,y,z) return {x,y,z,1,0,0,0,1,0,0,0,1} end
local identity=cf(0,0,0)
local shifted=cf(0.1,0.2,0.3)

local function animation(timePosition)
    return {humanoidState="Running",tracks={{
        animationId="rbxassetid://1",name="Walk",timePosition=timePosition,
        weightCurrent=0.75,weightTarget=1,speed=1,isPlaying=true,
        looped=true,priority="Movement",length=2,
    }}}
end

local function snapshot(clockValue,camera,primary,head,localHead,jointTransform,timePosition)
    return {
        clock=clockValue,cameraReadClock=clockValue+0.001,poseReadClock=clockValue+0.002,
        captureEndClock=clockValue+0.003,captureDurationMs=3,
        cameraCFrame=camera,fieldOfView=90,viewport={200,200},
        primaryCFrame=primary,headCFrame=head,primaryToHead=localHead,
        joints={Neck={name="Neck",part0="UpperTorso",part1="Head",transform=jointTransform,c0=identity,c1=identity}},
        animation=animation(timePosition),
    }
end

local function sample(frame,route,clockValue,beforeHeadX,afterHeadX,timePosition)
    local before=snapshot(clockValue,cf(0,0,0),cf(0,0,0),cf(0,2,-10),cf(0,2,-10),identity,timePosition)
    local after=snapshot(clockValue+0.01,cf(1,0,0),cf(0.5,0,0),cf(2,2,-10),cf(1.5,2,-10),shifted,timePosition+0.01)
    return {
        frame=frame,phase=route,time=clockValue,dt=0.01,yawSigned=30,yaw=30,pitchSigned=0,pitch=0,
        headScreenBefore={beforeHeadX,100,6},headScreenAfter={afterHeadX,100,6},
        primaryScreenBefore={50,120,6},primaryScreenAfter={50,120,6},
        subjectScreenBefore={40,110,6},subjectScreenAfter={40,110,6},
        temporalPoseTelemetry={cameraModuleBefore=before,cameraModuleAfter=after,
            controllerCalls={{before=before,after=after}}},
    }
end

local function metric(dx)
    return {start={0,0,6},finish={dx,0,6},dx=dx,dy=0,x=math.abs(dx)/60,y=0,displacement=math.abs(dx)/60}
end

local function segment(route,window,id,index,headDX)
    local first=sample(index*10+1,route,index,0,headDX*0.4,index)
    local second=sample(index*10+2,route,index+0.01,headDX*0.4,headDX,index+0.01)
    return {
        id=id,route=route,window=window,startFrame=first.frame,endFrame=second.frame,
        startTime=first.time,endTime=second.time+second.dt,duration=0.02,frameCount=2,
        totalSignedYaw=60,totalAbsYaw=60,netPitch=0,totalAbsPitch=0,
        yawTrajectory={30,30},pitchTrajectory={0,0},
        primary=metric(0),head=metric(headDX),subject=metric(0),
        returnedPrimary=metric(0),returnedHead=metric(headDX),returnedSubject=metric(0),
        subjectToPrimaryStart={0,-1.5,0},subjectToPrimaryEnd={0,-1.5,0},
        subjectToHeadStart={0,0.5,0},subjectToHeadEnd={0.1,0.5,0},
        primaryToHeadStart={0,2,0},primaryToHeadEnd={0.1,2,0},
        cameraYawStart=0,cameraYawEnd=1,cameraPitchStart=0,cameraPitchEnd=0,
        returnedYawEnd=1,returnedPitchEnd=0,samples={first,second},
    }
end

local raw={touch={},relay={}}
for index=1,32 do
    local suffix=string.format("%02d",index)
    local touchDX=index==1 and 1.2 or index==5 and 1.0 or 0.8
    local relayDX=index==1 and 0.6 or index==5 and 0.5 or 0.4
    raw.touch[index]=segment("touch",index%2==1 and "A1" or "A2","touch-"..suffix,index,touchDX)
    raw.relay[index]=segment("relay",index%2==1 and "B1" or "B2","relay-"..suffix,index+40,relayDX)
end

local durationGaps={0,0.02,0.05,0.08}
local features={touch={},relay={}}
local function feature(route,index)
    local suffix=string.format("%02d",index)
    local duration=0.1
    if route=="relay" then duration+=durationGaps[index] or 0.2 end
    return {
        id=route.."-"..suffix,route=route,window=raw[route][index].window,
        startTime=index,endTime=index+duration,duration=duration,frameCount=4,
        totalSignedYaw=60,totalAbsYaw=60,netPitch=0,totalAbsPitch=1,
        initialLocalHead=identity,initialCamera=identity,initialPrimary=identity,
        cameraToPrimary=identity,initialHeadDepth=10,fieldOfView=90,viewport={200,200},
        humanoidState="Running",animationAdvance=0.1,
        animationPhase=0,animationPhaseFraction=0,
        dominantTrack={key="track-"..suffix,length=2,looped=true,timePosition=0,
            speed=1,weightCurrent=0.75,weightTarget=1,isPlaying=true},
        headHorizontal=raw[route][index].head.x,
        primaryHorizontal=raw[route][index].primary.x,
        subjectHorizontal=raw[route][index].subject.x,
        segmentRef=raw[route][index],
    }
end
for index=1,32 do
    features.touch[index]=feature("touch",index)
    features.relay[index]=feature("relay",index)
end

local baseline={
    {yawGap=0.1,netPitchGap=0.02,absPitchGap=0.03,touch=raw.touch[1],relay=raw.relay[1]},
    {yawGap=0.2,netPitchGap=0.01,absPitchGap=0.04,touch=raw.touch[5],relay=raw.relay[5]},
}
local frozen={baseline=baseline,features=features,profiles={}}
local profiles=SEGCFG.controlledProfiles()
for _,name in ipairs({"Strict","Moderate","Broad"}) do
    frozen.profiles[name]=SEGCFG.runControlledProfile(features,profiles[name])
end
expect(#frozen.profiles.Strict.pairs==2,"literal Strict selection")
expect(#frozen.profiles.Moderate.pairs==3,"literal Moderate selection")
expect(#frozen.profiles.Broad.pairs==4,"literal Broad selection")
expect(frozen.profiles.Strict.pairs[2].touch.id=="touch-02","controlled-only pair selected")

local diagnostics={version="V614-test",callbackErrors=0,controllerErrors=0,
    frameCorrelationErrors=0,telemetryCaptureErrors=0,matchedComparisonUnits=2}
local model=SEGCFG.buildEssentialModel(frozen,diagnostics)
expect(model.schema=="V614-EssentialReportR2-TemporalPoseControl","R2 schema")
expect(countKeys(model.segments)==10,"segment telemetry deduplicated over selection union")
expect(#model.eligibleFeatures.touch==32,"all Touch features retained")
expect(#model.eligibleFeatures.relay==32,"all relay features retained")
expect(model.eligibleFeatures.touch[1].segmentRef==nil,"Touch segmentRef omitted")
expect(model.eligibleFeatures.relay[1].segmentRef==nil,"relay segmentRef omitted")
expect(#model.pairSets.Baseline==2,"baseline pair set")
expect(#model.pairSets.Strict==2,"Strict pair set")
expect(#model.pairSets.Moderate==3,"Moderate pair set")
expect(#model.pairSets.Broad==4,"Broad pair set")
expect(model.pairSets.Baseline[1].touchKey==model.pairSets.Moderate[1].touchKey,
    "shared segment uses one stable key")
expect(model.segments[model.pairSets.Strict[2].touchKey]~=nil,
    "controlled-only segment retained in union")
expect(#model.constants.joints==1,"constant joint definition deduplication")
expect(#model.constants.animations==1,"track metadata deduplication")
expect(model.omissions.unmatchedAcceptedFrames~=nil,"omission manifest")

-- Exercise production-style serialization boundaries. The fake service stores
-- an independent plain-data payload so all following matching and analysis use
-- decoded data rather than the original model object.
local encodedPayload=nil
function HttpService:JSONEncode(value)
    encodedPayload=SEGCFG.deepCopyEssential(value)
    return "synthetic-json"
end
function HttpService:JSONDecode(text)
    expect(text=="synthetic-json","JSON payload token")
    return SEGCFG.deepCopyEssential(encodedPayload)
end
function SEGCFG.serializeEssentialModel(value) return HttpService:JSONEncode(value) end
function SEGCFG.deserializeEssentialModel(text) return HttpService:JSONDecode(text) end
model.acquisitionR3={fixedTargetPerWindow=80,armedSegments=105,
    rejectedArms={['animation-phase']=12},potentialModeratePairs=3}
local decoded=SEGCFG.deserializeEssentialModel(SEGCFG.serializeEssentialModel(model))
expect(decoded~=model and decoded.segments~=model.segments,"analysis input is decoded model")
expect(decoded.acquisitionR3.fixedTargetPerWindow==80
    and decoded.acquisitionR3.rejectedArms['animation-phase']==12,
    "R3 acquisition audit metadata survives Essential round-trip")

local matchingEqual=true
for _,name in ipairs({"Strict","Moderate","Broad"}) do
    local rebuilt=SEGCFG.runControlledProfile(decoded.eligibleFeatures,profiles[name])
    local selection=SEGCFG.comparePairSelections(frozen.profiles[name],rebuilt)
    expect(selection.equal,name.." matching parity: "..table.concat(selection.mismatches or {},"|"))
    matchingEqual=matchingEqual and selection.equal
end

local fullAnalysis=SEGCFG.analyzeFullMatchedPairs(frozen)
local essentialAnalysis=SEGCFG.analyzeEssentialModel(decoded)
local analysisParity=SEGCFG.compareAnalysisResults(fullAnalysis,essentialAnalysis)
expect(analysisParity.equal,"A/B parity: "..table.concat(analysisParity.mismatches or {},"|"))
local maxResidual=SEGCFG.maximumScreenXResidual(essentialAnalysis)
local parity={matchingEqual=matchingEqual,analysisEqual=analysisParity.equal,maxResidual=maxResidual}
expect(parity.matchingEqual,"controlled pair IDs/costs parity")
expect(parity.analysisEqual,"all profile analyses parity")
expect(parity.maxResidual==0,"exact decomposition residual")
expect(essentialAnalysis.profiles.Baseline.pairCount==2,"Baseline pair count")
expect(essentialAnalysis.profiles.Strict.pairCount==2,"Strict pair count")
expect(essentialAnalysis.profiles.Moderate.pairCount==3,"Moderate pair count")
expect(essentialAnalysis.profiles.Broad.pairCount==4,"Broad pair count")
expect(essentialAnalysis.profiles.Moderate.pairs[1].touch.id=="touch-01"
    and essentialAnalysis.profiles.Moderate.pairs[1].touch.window=="A1"
    and essentialAnalysis.profiles.Moderate.pairs[1].relay.id=="relay-01"
    and essentialAnalysis.profiles.Moderate.pairs[1].relay.window=="B1",
    "controlled pair identity and ABBA windows")
expect(essentialAnalysis.profiles.Moderate.bootstrap.headDecomposition.endpoint.n==3,
    "Moderate Head endpoint paired CI")
expect(essentialAnalysis.profiles.Moderate.bootstrap.headDecomposition.within.n==3,
    "Moderate Head within-update paired CI")
expect(essentialAnalysis.profiles.Moderate.bootstrap.headDecomposition.between.n==3,
    "Moderate Head between-frame paired CI")
expect(essentialAnalysis.profiles.Moderate.initialPoseDistributions.cameraRotationGapDeg.n==3,
    "Moderate initial camera rotation gap distribution")
expect(essentialAnalysis.profiles.Moderate.initialPoseDistributions.localHeadTranslationGap.n==3,
    "Moderate initial local Head gap distribution")
local controlledDecision=SEGCFG.controlledDecision({profiles=essentialAnalysis.profiles,
    parity={equal=analysisParity.equal}},12)
expect(controlledDecision.temporalConfoundResolved=="unproved: insufficient controlled overlap",
    "fixture Moderate n<12 blocks decision")
expect(controlledDecision.initialPoseConfoundResolved=="unproved: insufficient controlled overlap",
    "fixture Moderate n<12 blocks pose decision")
expect(controlledDecision.causalMechanismProved==false
    and controlledDecision.implementationTargetIdentified==false
    and controlledDecision.v615Justified==false
    and controlledDecision.astra6MaxJustified==false
    and controlledDecision.pcEquivalenceClaimAllowed==false,
    "fixture Moderate n<12 blocks every promotion")

model.analysis=essentialAnalysis
model.parity={equal=analysisParity.equal,mismatches=analysisParity.mismatches,
    fullDigest="full",essentialDigest="essential",precisionDecimals=7}
model.decision=controlledDecision
model.config={}
model.windows={A1={},B1={},B2={},A2={}}
local report=SEGCFG.buildEssentialReportText({diagnostics={},model=model,matched=baseline,
    parity={equal=analysisParity.equal},modelJson="{}"},
    {fullReportChars=100000,essentialReportChars=20000,reductionPercent=80,essentialChunks=1})
expect(string.find(report,'acquisitionR3 = synthetic-json',1,true)~=nil,
    "R3 fixed acquisition and arm losses exported without entering causal analysis")
local sectionNames={
    "=== V614 BASELINE MATCHER (UNCHANGED) ===",
    "=== V614 CONTROLLED STRICT ===",
    "=== V614 CONTROLLED MODERATE (PRIMARY) ===",
    "=== V614 CONTROLLED BROAD ===",
    "=== V614 CONTROLLED SENSITIVITY SUMMARY ===",
    "=== V614 TEMPORAL + INITIAL-POSE DECISION ===",
}
local previous=0
for _,section in ipairs(sectionNames) do
    local position=string.find(report,section,1,true)
    expect(position~=nil and position>previous,"report section order: "..section)
    previous=position
end
for _,field in ipairs({"publishedBaselineHeadEffectStatus","controlledPairCount",
    "controlledGapDistributions","controlledHorizontalResults","controlledBootstrap",
    "controlledRouteDistributions","controlledInitialPoseDistributions",
    "controlledRejectionCounts","controlledCoverage","controlledPairDecomposition",
    "controlledCandidateCount","controlledPairIdentity","qualitativeOnlyEmergencyModeClue"}) do
    expect(string.find(report,field,1,true)~=nil,"report field: "..field)
end
expect(string.find(report,"causalMechanismProved = false",1,true)~=nil,"report blocks mechanism")
expect(string.find(report,"implementationTargetIdentified = false",1,true)~=nil,"report blocks target")
expect(string.find(report,"v615Justified = false",1,true)~=nil,"report blocks V615")
expect(string.find(report,"astra6MaxJustified = false",1,true)~=nil,"report blocks Astra")
expect(string.find(report,"pcEquivalenceClaimAllowed = false",1,true)~=nil,"report blocks equivalence")

local touch=essentialAnalysis.profiles.Baseline.pairs[1].touch
expect(touch.duration==0.02,"duration preserved")
expect(touch.frameCount==2,"frame count preserved")
expect(touch.screenX.head.within==0.02,"within-update Head decomposition")
expect(touch.screenX.head.between==0,"inter-frame Head decomposition")
expect(touch.screenX.head.residual==0,"Head residual")
expect(touch.screenX.primary.residual==0,"PrimaryPart residual")
expect(touch.screenX.subject.residual==0,"subject residual")
expect(touch.rootTranslation==0.5,"PrimaryPart/root translation")
expect(touch.rootPathTranslation==1.5,"PrimaryPart/root temporal path")
expect(touch.localHeadTranslation==1.5,"PrimaryPart-relative Head translation")
expect(touch.localHeadPathTranslation==4.5,"PrimaryPart-relative Head temporal path")
expect(touch.joints.Neck.translation==0.3741657,"Neck Transform translation")
expect(touch.joints.Neck.pathTranslation==1.1224972,"Neck Transform temporal path")
expect(touch.animations[1].timeAdvance==0.02,"animation TimePosition advance")
expect(touch.animations[1].weightChange==0,"animation weight change")
expect(touch.projection.cameraOnlyHeadDX==-10,"camera-only projection")
expect(touch.projection.poseOnlyHeadDX==20,"pose-only projection")
expect(touch.projection.combinedHeadDX==10,"combined projection")
expect(essentialAnalysis.profiles.Baseline.pairs[1].initial.animationTimeGap==40,
    "initial animation phase gap")
expect(essentialAnalysis.profiles.Baseline.bootstrap.headHorizontal.n==2,
    "paired Head bootstrap input count")
expect(essentialAnalysis.profiles.Baseline.bootstrap.headHorizontal.estimate==-0.0091667,
    "paired Head effect estimate")

-- Missing decomposition is invalid even when both A and B omit the same
-- point, preventing a false-equal parity gate.
local missingA=SEGCFG.deepCopyEssential(fullAnalysis)
local missingB=SEGCFG.deepCopyEssential(essentialAnalysis)
missingA.profiles.Baseline.pairs[1].touch.screenX.subject=nil
missingB.profiles.Baseline.pairs[1].touch.screenX.subject=nil
expect(not SEGCFG.compareAnalysisResults(missingA,missingB).equal,
    "matching A/B omissions fail decomposition gate")

-- Pair-selection parity rejects malformed inputs even when both sides carry
-- the same malformed shape.
expect(not SEGCFG.comparePairSelections(nil,nil).equal,"nil/nil pair selections fail closed")
local emptyPair={pairs={{}},cardinality=1,totalCost=0,rejectionCounts={}}
expect(not SEGCFG.comparePairSelections(emptyPair,emptyPair).equal,"pairs={{}} fails closed")
local validSelection=frozen.profiles.Strict
local badIds=SEGCFG.deepCopyEssential(validSelection); badIds.pairs[1].touchId=""
expect(not SEGCFG.comparePairSelections(badIds,badIds).equal,"invalid pair IDs fail closed")
local badCosts=SEGCFG.deepCopyEssential(validSelection); badCosts.pairs[1].integerCost=-1
expect(not SEGCFG.comparePairSelections(badCosts,badCosts).equal,"invalid pair costs fail closed")
local badCardinality=SEGCFG.deepCopyEssential(validSelection); badCardinality.cardinality=99
expect(not SEGCFG.comparePairSelections(badCardinality,badCardinality).equal,
    "invalid cardinality fails closed")
local badRejections=SEGCFG.deepCopyEssential(validSelection); badRejections.rejectionCounts["bad"]=-1
expect(not SEGCFG.comparePairSelections(badRejections,badRejections).equal,
    "invalid rejection counts fail closed")

local sizedText,sized=SEGCFG.solveEssentialReportSize(100000,29500,function(size)
    return "fullReportChars = "..size.fullReportChars
        .."\nessentialReportChars = "..size.essentialReportChars
        .."\nreductionPercent = "..SEGCFG.roundEssential(size.reductionPercent)
        .."\nessentialChunks = "..size.essentialChunks
end)
expect(utf8.len(sizedText)==sized.essentialReportChars,"essential char count fixed point")
expect(sized.essentialChunks==math.max(1,math.ceil(sized.essentialReportChars/29500)),"essential chunk count")

-- Real preparation -> production bundle -> decoded rematching -> report and
-- transport. Only Roblox diagnostics/JSON/legacy-size service boundaries are substituted.
environment.PCV614Diagnostics=function() return {version="failure-fixture",validationReady=false} end
SEGCFG.getWindowStats=function() return {} end
SEGCFG.buildLegacyReport=function() return 100000 end
local ordinaryRaw=SEGCFG.deepCopyEssential(raw)
for _,touch in ipairs(ordinaryRaw.touch) do touch.duration=nil end
segmentStats.touch.eligible=ordinaryRaw.touch
segmentStats.relay.eligible=ordinaryRaw.relay
SEGCFG.controlledResults=nil
local prepared=SEGCFG.prepareControlledMatching()
expect(prepared~=nil and #prepared.baseline==32,"missing features preserve real baseline pairs")
local ordinaryBundle=SEGCFG.buildProductionEssentialBundle()
expect(#ordinaryBundle.model.eligibleFeatures.touch==32 and #ordinaryBundle.model.eligibleFeatures.relay==32,
    "invalid compact features preserve the 32+32 eligible universe")
expect(ordinaryBundle.model.eligibleFeatures.touch[1].valid==false
    and ordinaryBundle.model.eligibleFeatures.touch[1].invalidReason=="missing segment duration",
    "compact invalid marker and extraction reason survive export")
expect(ordinaryBundle.parity.matchingEqual and ordinaryBundle.parity.analysisEqual,
    "real invalid feature rematching and baseline analysis parity")
for _,name in ipairs({"Strict","Moderate","Broad"}) do
    expect(ordinaryBundle.model.pairSetStats[name].rejectionCounts["missing segment duration"]==1024,
        name.." accounts for every rejected candidate")
    expect(ordinaryBundle.model.analysis.profiles[name].pairCount==0,name.." has no invalid pairs")
end
expect(ordinaryBundle.model.decision.temporalConfoundResolved=="unproved: insufficient controlled overlap",
    "ordinary rejection reports insufficient overlap")
local ordinaryReport=environment.PCV614EssentialReport()
expect(string.find(ordinaryReport,"baselinePairCount = 32",1,true)~=nil,
    "ordinary missing duration keeps Baseline exportable")
expect(string.find(ordinaryReport,"controlledRejectionCounts",1,true)~=nil,
    "ordinary report carries rejection counts")
local function verifyFailureTransport(report)
    local chars=SEGCFG.reportCharCount(report)
    expect(string.find(report,"essentialReportChars = "..chars,1,true)~=nil,"failure report exact size")
    local chunks=SEGCFG.splitReportPayloads(report,29500)
    expect(table.concat(chunks)==report,"failure report lossless chunk fallback")
    local copied=nil
    expect(SEGCFG.copyCompleteReport({chunks=chunks,totalReportChars=chars},function(text)
        copied=text; return true
    end),"failure report complete copy succeeds")
    expect(copied==report,"failure report one-tap exact content")
    for _,flag in ipairs({"v615Justified","astra6MaxJustified","implementationTargetIdentified",
        "pcEquivalenceClaimAllowed","causalMechanismProved"}) do
        expect(string.find(report,flag.." = false",1,true)~=nil,"failure report blocks "..flag)
    end
end
verifyFailureTransport(ordinaryReport)

segmentStats.touch.eligible={[1]=ordinaryRaw.touch[1],[3]=ordinaryRaw.touch[3]}
SEGCFG.controlledResults=nil
SEGCFG.buildLegacyReport=function() error("legacy cannot analyze corrupt list",0) end
local structuralReport=environment.PCV614EssentialReport()
expect(string.find(structuralReport,"diagnosticOnly = true",1,true)~=nil,
    "structural failure remains exportable as explicitly diagnostic-only")
expect(string.find(structuralReport,"eligible-list-invalid",1,true)~=nil,
    "structural diagnostic retains audit reason")
expect(string.find(structuralReport,"fullReportChars = unavailable",1,true)~=nil
    and string.find(structuralReport,"reductionPercent = unavailable",1,true)~=nil,
    "failed legacy report size is unavailable, never fabricated")
expect(string.find(structuralReport,"analysisParity = false",1,true)~=nil
    and string.find(structuralReport,"baselinePairCount =",1,true)==nil,
    "structural diagnostic does not invent analysis")
verifyFailureTransport(structuralReport)
print("PASS: ordinary rejection preserves Baseline, 32+32 features, counts, parity, and mobile export")
print("PASS: structural failure exports an audited diagnostic with no invented analysis")

print("PASS: V614 R2 deduplicates retained telemetry and preserves 32+32 compact features")
print("PASS: decoded controlled selections and all profile analyses have exact parity")
print("PASS: Head/PrimaryPart/subject decomposition is complete with zero residual")
print("PASS: malformed selections and matching decomposition omissions fail closed")
print("PASS: V614 essential size fields converge exactly")
'''
)

with tempfile.TemporaryDirectory(prefix="v614-essential-test-") as temp_dir:
    test_path = Path(temp_dir) / "essential_test.luau"
    test_path.write_text(program, encoding="utf-8")
    completed = subprocess.run(
        [str(luau_binary()), str(test_path)],
        check=False,
        text=True,
        capture_output=True,
    )
    if completed.stdout:
        print(completed.stdout, end="")
    if completed.stderr:
        print(completed.stderr, end="")
    raise SystemExit(completed.returncode)
