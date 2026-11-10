"""Offline model + source contract checks for the native Classic Thumbstick project.

Run at repository root: python3 tests/native-classic/test_contracts.py
NOTE: These do NOT simulate the Roblox engine or prove iPhone timing/FPS.
"""
from __future__ import annotations

from math import hypot, isclose
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BOOST = (ROOT / "ClassicNativeBoostV1.lua").read_text(encoding="utf-8")
ASSIST = (ROOT / "ClassicNativeGridAssistV1.lua").read_text(encoding="utf-8")
LOADER = (ROOT / "ClassicNativeBoostAssistLoader.lua").read_text(encoding="utf-8")


def shape(x: float, z: float, start: float = 0.08, full: float = 0.58):
    if abs(x) > start:
        new_x = (1 if x > 0 else -1) * min(1, max(0, (abs(x) - start) / (full - start)))
    else:
        new_x = 0
    length = hypot(new_x, z)
    if length > 1:
        new_x /= length
        z /= length
    return new_x, z


def near(a, b, eps=1e-9):
    return isclose(a, b, abs_tol=eps, rel_tol=0)


def run_model_tests():
    assert shape(0, 0) == (0, 0), "release must never become phantom input"
    assert shape(-0.58, 0)[0] < -0.999999, "left must reach full strength"
    assert shape(0.58, 0)[0] > 0.999999, "right must reach full strength"
    assert shape(-1, 0) == (-1, 0), "full left"
    assert shape(1, 0) == (1, 0), "full right"
    assert shape(0, -1) == (0, -1), "forward axis unchanged"
    assert shape(0, 1) == (0, 1), "backward axis unchanged"

    for x in (-1, -0.58, -0.3, -0.08, 0, 0.08, 0.3, 0.58, 1):
        for z in (-1, -0.6, 0, 0.6, 1):
            a, b = shape(x, z)
            assert hypot(a, b) <= 1.00000001, "vector cannot exceed normal magnitude"
            opposite, other = shape(-x, z)
            assert near(a, -opposite) and near(b, other), "left/right must be symmetric"

    # No temporal latch: zero and the other side respond on their first sample.
    direction = [shape(x, 0)[0] for x in (-0.9, -0.58, -0.05, 0.05, 0.58, 0.9)]
    assert direction == [-1, -1, 0, 0, 1, 1], direction
    for x in (0.3, 0.6, 0.9):
        assert shape(x, -0.7)[0] > 0 and shape(-x, -0.7)[0] < 0, "diagonal sign"
    return 45 + 7


def run_contract_tests():
    for token in (
        'activeModule.Name == "TouchThumbstick"',
        'activeController ~= c',
        'attached.GetMoveVector = originalOwnMethod',
        'return move',
        'SideFullAt = 0.58',
        'config.Enabled',
        'env.__ClassicNativeBoostV1Cleanup',
    ):
        assert token in BOOST, f"Missing native safety gate: {token}"
    for token in ("Instance.new(\"ScreenGui\")", "VirtualInputManager", "SendKeyEvent",
                  "BindToRenderStep", "player:Move(", "TouchGui.Enabled = false"):
        assert token not in BOOST, f"Native boost must not own UI/keys/frames: {token}"
    for token in ('return flatUnit(humanoid.MoveDirection)', 'humanoid.AutoRotate',
                  'CONTACT_SCAN_INTERVAL=1/12', 'env.ClassicNativeGridAssistV1',
                  'api.SetEnabled=', 'horizontalWrites=0,verticalWrites=0'):
        assert token in ASSIST, f"Missing low-impact Assist contract: {token}"
    for token in ("VirtualInputManager", "SendKeyEvent", "AssemblyLinearVelocity=",
                  "AssemblyLinearVelocity = ", "humanoid.Jump=", "humanoid.Jump ="):
        assert token not in ASSIST, f"Assist must not override motion/jump: {token}"
    for token in ("ClassicNativeBoostV1.lua", "ClassicNativeGridAssistV1.lua",
                  "function api.Stop()", "function api.SetAssist(value)"):
        assert token in LOADER, f"Loader contract absent: {token}"


if __name__ == "__main__":
    count = run_model_tests()
    run_contract_tests()
    print(f"PASS native classic model ({count} conceptual checks) and source contracts")
