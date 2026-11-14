-- Deterministic traces for the real bridge, native visual and light Assist.
-- All engine calls go to fixtures. CPU time here belongs to the Luau host.
local clock=os.clock
local F=dofile("tests/v31-preserved/RobloxFixture.lua")
local E=dofile("tests/v31-preserved/Environment.lua")
local fixture=dofile("tests/v32/Fixture.lua")
local noPosture=function() return function() end end
local FRAMES=12000
local RUNS=7

local function run(version,scenario,withCounts)
    local e=fixture(F,E)
    BENCH_COUNTS={sectors=0,knob=0}
    local keyEvents=0
    e.services.VirtualInputManager.SendKeyEvent=function() keyEvents+=1 end
    if version==31 then
        dofile(withCounts and "@baseline-counter-bridge" or "PCKeyboardTouchBridgeV3.lua")
        dofile("LegacyGridContactAssistV31Preserved.lua")
    else
        dofile("v32/Bridge.lua")(noPosture)
        dofile("@v32-assist")
    end
    dofile("@original-visual")

    local overlay=e.pg:FindFirstChild("PCKeyboardTouchBridgeV52Overlay")
    local stick=overlay:FindFirstChild("PCJoystick")
    local jump=overlay:FindFirstChild("PCJump")
    local center=stick.AbsolutePosition+stick.AbsoluteSize/2
    local movement={UserInputType=Enum.UserInputType.Touch,Position=center+Vector2.new(-28,0)}
    local jumpFinger={UserInputType=Enum.UserInputType.Touch,Position=jump.AbsolutePosition+jump.AbsoluteSize/2}
    local left,right=center+Vector2.new(-40,-34),center+Vector2.new(40,-34)
    e.hum.MoveDirection=Vector3.zero
    if scenario~="idle" then e.uis.InputBegan:fire(movement) end
    if scenario=="turn+jump+grid" then
        local fence=e:part("FenceBench")
        e.parts={fence}
        e.raycast=function(origin)
            return {Instance=fence,Position=Vector3.new(2,origin.Y,0),Normal=Vector3.new(-1,0,0)}
        end
    end

    local start=clock()
    for i=1,FRAMES do
        if scenario=="turn+jump+grid" then
            movement.Position=i%2==0 and left or right
            e.uis.InputChanged:fire(movement)
            if i%15==1 then
                e.uis.InputBegan:fire(jumpFinger)
                e.uis.InputEnded:fire(jumpFinger)
            end
        end
        e:step(1/60)
    end
    local elapsed=(clock()-start)*1000
    local state=e.env.PCKeyboardTouchBridgeV52.GetState()
    local contact=e.env.LegacyGridContactAssistV1.GetState()
    local result={elapsed=elapsed,keys=keyEvents,rays=e.rays,queries=e.queries,
        scans=contact.scanCount,jumpPulses=state.jumpPulses,
        sectors=state.sectorEvaluations or BENCH_COUNTS.sectors,knob=state.knobWrites or BENCH_COUNTS.knob}
    e.env.__LegacyGridContactAssistV1Cleanup()
    e.env.__PCRobloxNativeVisualV5Cleanup()
    e.env.__PCKeyboardTouchBridgeV52Cleanup()
    return result
end

print("Benchmark Luau host, 12,000 frames per trace, median of 7 alternating pairs (ms)")
for _,scenario in ipairs({"idle","held","turn+jump+grid"}) do
    local timings={[31]={},[32]={}}
    for sample=1,RUNS do
        local first=sample%2==1 and 31 or 32
        for _,version in ipairs({first,63-first}) do
            timings[version][sample]=run(version,scenario,false).elapsed
        end
    end
    for version=31,32 do
        local result=run(version,scenario,true)
        table.sort(timings[version])
        local times=timings[version]
        print(string.format("%s v%d: %.2f ms [%.2f, %.2f], sectors=%d, knob=%d, keys=%d, pulses=%d, scans=%d, rays=%d, overlaps=%d",
            scenario,version,times[4],times[1],times[7],result.sectors,result.knob,result.keys,
            result.jumpPulses,result.scans,result.rays,result.queries))
        if version==32 and scenario=="idle" then
            assert(result.sectors==0 and result.knob==0,"idle still performs bridge work")
        elseif version==32 and scenario=="held" then
            assert(result.sectors==1 and result.knob==1,"stationary thumb still performs bridge work")
        end
        if scenario=="turn+jump+grid" then assert(result.jumpPulses>(version==31 and 5000 or 600) and result.rays>0) end
    end
end
