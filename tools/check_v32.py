#!/usr/bin/env python3
"""Validate the packed V3.2 with the Luau CLI. Optional deterministic host benchmark."""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.dont_write_bytecode = True
import build_v32

ROOT = build_v32.ROOT
os.chdir(ROOT)


def verify_base():
    changed = subprocess.check_output(
        ["git", "diff", "--diff-filter=DMRTUXB", "--name-only", build_v32.BASE], text=True
    )
    if changed:
        raise SystemExit(f"V3.1 tracked files changed:\n{changed}")
    print("PASS base: preserved V3.1 files unchanged, bundle reproducible", flush=True)


def make_harness(sources):
    header = ["local factories={}"]
    for path, source in sources.items():
        header += [f"factories[{json.dumps(path)}]=function()", source.rstrip(), "end"]
    header += [
        "local function factory(path) return assert(factories[path],path)() end",
        "local dofile=factory",
        "local TEST_BASELINE=false",
        "",
    ]
    return "\n".join(header)


def run_suite(luau, compiler, bench):
    paths = [
        "PC_Movement_V32.lua",
        "PCKeyboardTouchBridgeV3.lua",
        "LegacyGridContactAssistV31Preserved.lua",
        "v32/Bridge.lua",
        "v32/Posture.lua",
        "tests/v31-preserved/RobloxFixture.lua",
        "tests/v31-preserved/Environment.lua",
        "tests/v32/Fixture.lua",
    ]
    sources = {path: Path(path).read_text() for path in paths}
    sources["@v32-assist"] = build_v32.assist_source()
    sources["@original-visual"] = build_v32.snapshot(build_v32.CLASSIC, "PCRobloxNativeVisualV5.lua")
    baseline = sources["PCKeyboardTouchBridgeV3.lua"]
    baseline = build_v32.replace(baseline, "local function refreshKeys(now)\n",
                                 "local function refreshKeys(now)\n    BENCH_COUNTS.sectors+=1\n")
    baseline = build_v32.replace(baseline, "knob.Position=UDim2.",
                                 "BENCH_COUNTS.knob+=1\n        knob.Position=UDim2.", count=4)
    sources["@baseline-counter-bridge"] = baseline
    with tempfile.TemporaryDirectory(prefix="pc-movement-v32-") as folder:
        folder = Path(folder)
        tests = sorted(Path("tests/v32").glob("*_test.lua"))
        for test in tests:
            harness = folder / test.name
            harness.write_text(make_harness(sources) + test.read_text())
            subprocess.run([luau, str(harness)], check=True)
        assist = Path("tests/v31-preserved/assist_test.lua").read_text()
        assist = build_v32.replace(assist, "dofile('LegacyGridContactAssistV31Preserved.lua')", """
local fixtureBridge=e.env.PCKeyboardTouchBridgeV52
fixtureBridge.ReadMovement=function()
    local state=fixtureBridge.GetState()
    return state.chord,state.analogX,state.analogZ,false,state.jumpPulses
end
dofile('@v32-assist')""")
        harness = folder / "assist_test.lua"
        harness.write_text(make_harness(sources) + assist)
        subprocess.run([luau, str(harness)], check=True)
        print(f"PASS V3.2 suite: {len(tests)+1} Luau programs", flush=True)
        if bench:
            harness = folder / "benchmark.lua"
            harness.write_text(make_harness(sources) + Path("tests/v32/benchmark.lua").read_text())
            subprocess.run([luau, str(harness)], check=True)
    subprocess.run([compiler, "--null", "PC_Movement_V32.lua", *map(str, Path("v32").glob("*.lua"))], check=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bench", action="store_true")
    args = parser.parse_args()
    if build_v32.OUTPUT.read_text() != build_v32.render():
        raise SystemExit("Bundle stale. Run python3 tools/build_v32.py.")
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    compiler = os.environ.get("LUAU_COMPILE") or shutil.which("luau-compile")
    if not luau or not compiler:
        raise SystemExit("Set LUAU_BIN and LUAU_COMPILE to the Luau CLI executables.")
    verify_base()
    run_suite(luau, compiler, args.bench)
