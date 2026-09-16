#!/usr/bin/env python3
"""Execute V614 essential-report helpers with deterministic matched telemetry."""

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

if "getgenv().PCV614EssentialReport=function()" not in source:
    raise SystemExit("RED: PCV614EssentialReport entry point is missing")
if "local fullReport=getgenv().PCV614EssentialReport()" not in source:
    raise SystemExit("RED: chunk export is not wired to the essential report")
if 'local revision="V614-TemporalPoseTelemetryR1-EssentialReportR1"' not in loader_source:
    raise SystemExit("RED: Loader essential-report cache revision is missing")


program = (
    "local SEGCFG={}\n"
    + match.group(1)
    + r'''
local function expect(condition,message)
    if not condition then error(message,0) end
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
        subjectScreenBefore={50,120,6},subjectScreenAfter={50,120,6},
        temporalPoseTelemetry={cameraModuleBefore=before,cameraModuleAfter=after,
            controllerCalls={{before=before,after=after}}},
    }
end

local function metric(dx)
    return {start={0,0,6},finish={dx,0,6},dx=dx,dy=0,x=math.abs(dx)/60,y=0,displacement=math.abs(dx)/60}
end

local function segment(route,window,index,headDX)
    local first=sample(index*10+1,route,index,0,headDX*0.4,index)
    local second=sample(index*10+2,route,index+0.01,headDX*0.4,headDX,index+0.01)
    return {
        id=route.."-"..index,route=route,window=window,startFrame=first.frame,endFrame=second.frame,
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

local pairs={
    {yawGap=0.1,netPitchGap=0.02,absPitchGap=0.03,
        touch=segment("touch","A1",1,1.2),relay=segment("relay","B1",2,0.6)},
    {yawGap=0.2,netPitchGap=0.01,absPitchGap=0.04,
        touch=segment("touch","A2",3,1.0),relay=segment("relay","B2",4,0.5)},
}
local diagnostics={version="V614-test",callbackErrors=0,controllerErrors=0,
    frameCorrelationErrors=0,telemetryCaptureErrors=0,matchedComparisonUnits=2}

local model=SEGCFG.buildEssentialModel(pairs,diagnostics)
expect(#model.pairs==2,"matched-only pair count")
expect(#model.constants.joints==1,"constant joint definition deduplication")
expect(#model.constants.animations==1,"track metadata deduplication")
expect(model.omissions.unmatchedAcceptedFrames~=nil,"omission manifest")
expect(model.pairs[1].touch.boundaries.start~=nil,"start boundary")
expect(model.pairs[1].touch.boundaries.finish~=nil,"finish boundary")
expect(model.pairs[1].touch.series[1].jointTransform~=nil,"variable joint series")
expect(model.pairs[1].touch.series[1].cameraBefore==nil,"interior full Camera CFrame omitted")
expect(model.pairs[1].touch.series[1].primaryBefore==nil,"interior full PrimaryPart CFrame omitted")
expect(model.pairs[1].touch.series[1].localHeadBefore==nil,"interior full local Head CFrame omitted")
expect(model.pairs[1].touch.series[1].rootStep.withinTranslation==0.5,"root step retained")
expect(model.pairs[1].touch.series[2].rootStep.boundaryTranslation==0.5,"root boundary step retained")
expect(SEGCFG.roundEssential(model.pairs[1].touch.series[1].jointTransform.Neck.withinTranslation)==0.3741657,
    "joint step retained")

local fullAnalysis=SEGCFG.analyzeFullMatchedPairs(pairs)
local essentialAnalysis=SEGCFG.analyzeEssentialModel(model)
local parity=SEGCFG.compareAnalysisResults(fullAnalysis,essentialAnalysis)
expect(parity.equal,"A/B parity: "..table.concat(parity.mismatches or {},"|"))
local touch=essentialAnalysis.pairs[1].touch
expect(touch.duration==0.02,"duration preserved")
expect(touch.frameCount==2,"frame count preserved")
expect(touch.headWithinXPerYaw==0.02,"within-update Head decomposition")
expect(touch.headBoundaryXPerYaw==0,"inter-frame Head decomposition")
expect(touch.rootTranslation==0.5,"PrimaryPart/root translation")
expect(touch.rootPathTranslation==1.5,"PrimaryPart/root temporal path")
expect(touch.localHeadTranslation==1.5,"PrimaryPart-relative Head translation")
expect(touch.localHeadPathTranslation==4.5,"PrimaryPart-relative Head temporal path")
expect(touch.joints.Neck.translation==0.3741657,"Neck Transform translation")
expect(touch.joints.Neck.pathTranslation==1.1224972,"Neck Transform temporal path")
expect(touch.animations[1].timeAdvance==0.02,"animation TimePosition advance")
expect(touch.animations[1].weightChange==0,"animation weight change")
expect(touch.animations[1].key=="rbxassetid://1|Walk|Movement|true|2","animation identity preserved")
expect(touch.projection.cameraOnlyHeadDX==-10,"camera-only projection")
expect(touch.projection.poseOnlyHeadDX==20,"pose-only projection")
expect(touch.projection.combinedHeadDX==10,"combined projection")
expect(touch.projection.startHeadDepth==10,"projection start depth")
expect(touch.projection.finishHeadDepth==10,"projection finish depth")
expect(essentialAnalysis.pairs[1].initial.cameraRotationGapDeg==0,"initial camera rotation gap")
expect(essentialAnalysis.pairs[1].initial.animationTimeGap==1,"initial animation phase gap")
expect(essentialAnalysis.aggregates.touch.rootTranslation.mean==0.5,"root aggregate")
expect(essentialAnalysis.aggregates.touch.localHeadTranslation.mean==1.5,"local Head aggregate")
expect(essentialAnalysis.aggregates.touch.jointNeckTranslation.mean==0.3741657,"joint aggregate")
expect(essentialAnalysis.aggregates.touch.animationTimeAdvance.mean==0.02,"animation aggregate")
expect(essentialAnalysis.bootstrap.headHorizontal.n==2,"paired Head bootstrap input count")
expect(essentialAnalysis.bootstrap.headHorizontal.estimate==-0.0091667,"paired Head effect estimate")
expect(essentialAnalysis.method.blockSize==2,"bootstrap block constrained to available pairs")
expect(essentialAnalysis.method.iterations==2000,"bootstrap iterations preserved")
expect(essentialAnalysis.decisions.temporalConfoundResolved=="unproved","conservative temporal decision")
expect(essentialAnalysis.decisions.causalMechanismProved==false,"no causal mechanism claim")
expect(essentialAnalysis.decisions.implementationTargetIdentified==false,"no implementation target claim")

local mutated=SEGCFG.deepCopyEssential(model)
mutated.pairs[1].touch.series[1].headAfterX=nil
local bad=SEGCFG.compareAnalysisResults(fullAnalysis,SEGCFG.analyzeEssentialModel(mutated))
expect(not bad.equal,"missing essential input must fail parity")

local sizedText,sized=SEGCFG.solveEssentialReportSize(100000,29500,function(size)
    return "fullReportChars = "..size.fullReportChars
        .."\nessentialReportChars = "..size.essentialReportChars
        .."\nreductionPercent = "..SEGCFG.roundEssential(size.reductionPercent)
        .."\nessentialChunks = "..size.essentialChunks
end)
expect(utf8.len(sizedText)==sized.essentialReportChars,"essential char count fixed point")
expect(sized.essentialChunks==math.max(1,math.ceil(sized.essentialReportChars/29500)),"essential chunk count")
expect(sized.reductionPercent==SEGCFG.roundEssential((1-sized.essentialReportChars/100000)*100),"reduction arithmetic")

print("PASS: V614 full and essential analyses are identical at report precision")
print("PASS: missing essential input is detected by parity gate")
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
