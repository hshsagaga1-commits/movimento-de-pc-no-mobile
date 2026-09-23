#!/usr/bin/env python3
"""Exercise V614 R3's route-neutral acquisition rules in standalone Luau."""

from __future__ import annotations

import hashlib
from pathlib import Path
import re
import subprocess
import tempfile

from V614_TEMPORAL_POSE_CONTROL_TEST import PROTECTED_SECTIONS, extract_section


ROOT = Path(__file__).resolve().parent
SOURCE = (ROOT / "PCMovementV614_ControlledYawPitchMatching.lua").read_text()
START = "-- BEGIN V614 ACQUISITION R3 PURE HELPERS\n"
END = "-- END V614 ACQUISITION R3 PURE HELPERS"


def main() -> None:
    if START not in SOURCE or END not in SOURCE:
        raise SystemExit("RED: V614 R3 pure acquisition helper is missing")
    helper = SOURCE.split(START, 1)[1].split(END, 1)[0]
    for name in ("matchSegments", "standingObservation", "recordPairedSample",
                 "closeCurrentSegment", "updateCoverageState"):
        digest = hashlib.sha256(extract_section(SOURCE, name).encode()).hexdigest()
        expected = PROTECTED_SECTIONS[name][2]
        if digest != expected:
            raise SystemExit(f"RED: protected {name} changed: {digest}")
    if not re.search(r"phaseEligibleTarget=80,routeEligibleTarget=160", SOURCE):
        raise SystemExit("RED: fixed 80-per-window R3 target is missing")
    if 'sequence={"A1","B1","B2","A2"}' not in SOURCE:
        raise SystemExit("RED: ABBA changed")
    for literal in ("SEGCFG.acquisitionR3Eligible(before", "SEGCFG.refreshLiveModerate",
                    "COPIAR REPORT ESSENCIAL COMPLETO"):
        if literal not in SOURCE:
            raise SystemExit(f"RED: R3 hook/UI missing {literal}")
    status = SOURCE.split("refreshLiveStatus=function()", 1)[1].split("\nlocal function createPanel()", 1)[0]
    if "SEGCFG.matchSegments()" in status or "SEGCFG.livePotentialPairs" not in status:
        raise SystemExit("RED: UI must read cached baseline coverage, not solve every 50 ms")

    fixture = r'''
local SEGCFG={}
function SEGCFG.controlledDominantTrack(animation)
    if type(animation)~="table" or type(animation.track)~="table" then return nil,"missing-track" end
    local track=animation.track
    if track.isPlaying~=true or track.weightCurrent<=0 then return nil,"inactive-track" end
    return track
end
function SEGCFG.controlledRelativeRotation(_,camera)
    return camera
end
function SEGCFG.controlledRotationGapDeg(a,b)
    return math.abs(a[1]-b[1])
end
function SEGCFG.controlledInitialHeadDepth(_,head)
    return head[1]
end
local function snap(phase)
    return {
        animation={humanoidState="Running",track={key="Idle",length=2,looped=true,
            timePosition=phase*2,isPlaying=true,weightCurrent=1}},
        cameraCFrame={0},primaryCFrame={0},headCFrame={6},primaryToHead={0,1.5,0},
        fieldOfView=90,viewport={800,414},
    }
end
''' + helper + r'''
local function expect(value,message)
    if not value then error(message,0) end
end
local reference=SEGCFG.acquisitionR3Reference(snap(0.50))
expect(reference~=nil,"neutral reference")
local sample=snap(0.50)
expect(SEGCFG.acquisitionR3Eligible(sample,reference)==true,"same pose in either route")
expect(SEGCFG.acquisitionR3Eligible(snap(0.455),reference)==true,"lower phase boundary")
expect(SEGCFG.acquisitionR3Eligible(snap(0.545),reference)==true,"upper phase boundary")
expect(SEGCFG.acquisitionR3Eligible(snap(0.30),reference)==false,"phase outside band")
sample=snap(0.5);sample.primaryToHead[1]=0.026
expect(SEGCFG.acquisitionR3Eligible(sample,reference)==false,"translation exceeds half caliper")
sample=snap(0.5);sample.cameraCFrame[1]=2.6
expect(SEGCFG.acquisitionR3Eligible(sample,reference)==false,"camera orientation exceeds half caliper")
sample=snap(0.5);sample.headCFrame[1]=6.03
expect(SEGCFG.acquisitionR3Eligible(sample,reference)==false,"depth exceeds half caliper")
sample=snap(0.5);sample.animation.track.key="Other"
expect(SEGCFG.acquisitionR3Eligible(sample,reference)==false,"dominant track must match")
sample=snap(0.5);sample.animation.humanoidState="Jumping"
expect(SEGCFG.acquisitionR3Eligible(sample,reference)==false,"state must match")
sample=snap(0.5);sample.viewport[1]=900
expect(SEGCFG.acquisitionR3Eligible(sample,reference)==false,"viewport must match")
sample=snap(0.5);sample.animation=nil
expect(SEGCFG.acquisitionR3Eligible(sample,reference)==false,"missing animation fails closed")
expect(SEGCFG.acquisitionR3Reference(snap(0.47))==nil,"reference phase tighter")
print("PASS: R3 acquisition is route-neutral, read-only and bounded by half Moderate pose limits")
'''
    with tempfile.TemporaryDirectory(prefix="v614-acquisition-r3-") as directory:
        script = Path(directory) / "acquisition.luau"
        script.write_text(fixture)
        binary = ROOT.parent / "tooling/luau-bin/luau"
        result = subprocess.run([binary, script], capture_output=True, text=True)
    if result.returncode or "PASS: R3 acquisition" not in result.stdout:
        raise SystemExit(result.stdout + result.stderr)
    coverage = extract_section(SOURCE, "updateCoverageState")
    state_fixture = r'''
local SEGCFG={phaseEligibleTarget=80,minMatched=12,livePotentialPairs=0}
local currentWindow="A1"
local phaseState="active"
local completedWindows={}
local evidence={}
local eligible=79
function SEGCFG.windowEligibleCount() return eligible end
function SEGCFG.matchSegments()
    local pairs={}
    for i=1,16 do pairs[i]=i end
    return pairs
end
local function addEvidence(_,value) evidence[#evidence+1]=value end
''' + coverage + r'''
SEGCFG.updateCoverageState({window="A1"})
assert(phaseState=="active" and completedWindows.A1==nil,
    "79 eligible must remain active even when 16 matched")
eligible=80
SEGCFG.updateCoverageState({window="A1"})
assert(phaseState=="complete" and completedWindows.A1==true,
    "80 eligible must freeze even without an outcome-based stop")
assert(SEGCFG.livePotentialPairs==16 and #evidence==1,
    "cached coverage must be refreshed once at segment closure")
print("PASS: R3 phase completion is fixed, independent of match count")
'''
    with tempfile.TemporaryDirectory(prefix="v614-r3-transition-") as directory:
        script = Path(directory) / "transition.luau"
        script.write_text(state_fixture)
        transition = subprocess.run([binary, script], capture_output=True, text=True)
    if transition.returncode or "PASS: R3 phase completion" not in transition.stdout:
        raise SystemExit(transition.stdout + transition.stderr)
    print(result.stdout.strip())
    print(transition.stdout.strip())
    print("PASS: Baseline, standing and segment closure protected functions unchanged")


if __name__ == "__main__":
    main()
