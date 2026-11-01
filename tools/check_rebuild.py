#!/usr/bin/env python3
"""Run the reconstruction's complete offline verification suite."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import json
import tempfile

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
def run(*args):
    subprocess.run(args, check=True)

run(sys.executable, "tools/build_rebuild.py", "--check")
lua = shutil.which("texlua") or shutil.which("lua")
assert lua, "Install Lua (5.3+) or texlua to execute offline tests"
tests = ("core_test.lua", "adapters_test.lua", "controls_test.lua", "runtime_test.lua", "route_mobile_test.lua")
for filename in tests:
    run(lua, f"tests/{filename}")

for path in (ROOT / "rebuild").glob("*.lua"):
    text = path.read_text()
    # All of these properties would change physical character/world behavior.
    assert not re.search(r"\.(?:AssemblyLinearVelocity|AssemblyAngularVelocity|Velocity|CFrame|WalkSpeed|"
                         r"JumpPower|JumpHeight|HipHeight|CanCollide|PlatformStand|AutoRotate)\s*=", text), path
    assert not re.search(r":\s*(?:Move|ApplyImpulse|ChangeState|SetStateEnabled)\s*\(", text), path
    assert not re.search(r'Instance\.new\(["\'](?:BodyVelocity|BodyPosition|VectorForce|LinearVelocity|'
                         r'AlignPosition|AlignOrientation)["\']', text), path
    assert "HttpGet" not in text and "loadstring" not in text, f"Runtime network dependency in {path}"
standalone = ROOT / "PC_Movement_Rebuild_AUTOEXECUTE.lua"
assert "HttpGet" not in standalone.read_text()

# Check original bytes, not merely the list of staged changes.
base = "ce4eb8b"
originals = subprocess.check_output(["git", "ls-tree", "-r", "--name-only", base], text=True).splitlines()
for name in originals:
    original = subprocess.check_output(["git", "show", f"{base}:{name}"])
    assert (ROOT / name).read_bytes() == original, f"Historical file was changed: {name}"
print(f"PASS: no physics writers, no runtime HTTP dependencies; {len(originals)} historical files intact", flush=True)

compiler = os.environ.get("LUAU_COMPILE") or shutil.which("luau-compile")
if compiler:
    files = [str(p) for p in sorted((ROOT / "rebuild").glob("*.lua"))]
    files += [str(standalone), str(ROOT / "PCMovementRebuildLoader.lua")]
    run(compiler, "--null", *files)
    interpreter = Path(compiler).with_name("luau")
    if interpreter.exists():
        # Luau CLI has no filesystem dofile/loadfile. Embed exact production
        # sources and the fixture without rewriting the tests or runtime logic.
        factories = []
        sources = list(sorted((ROOT / "rebuild").glob("*.lua"))) + [ROOT / "tests/RobloxFixture.lua"]
        for source in sources:
            name = source.relative_to(ROOT).as_posix()
            factories.append(f"factories[{json.dumps(name)}]=function()\n{source.read_text()}\nend\n")
        header = "local factories={}\n" + "\n".join(factories)
        header += ("local function loadfile(path) return factories[path] end\n"
                   "local function dofile(path) assert(factories[path],path); return factories[path]() end\n")
        with tempfile.TemporaryDirectory(prefix="pc-movement-luau-") as directory:
            for filename in tests:
                harness = Path(directory) / filename
                harness.write_text(header + (ROOT / "tests" / filename).read_text())
                run(str(interpreter), str(harness))
        print("PASS: the same production behavior suite executed in Luau CLI", flush=True)
else:
    print("Luau compiler not configured; behavior tests parsed Lua-compatible production sources. Set LUAU_COMPILE for engine syntax verification.")
