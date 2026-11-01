#!/usr/bin/env python3
"""Check the incremental V3.1 branch without executing Roblox or network calls."""
from pathlib import Path
import json, os, shutil, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT)
BASE='ce4eb8b6deb47e0690301bd38f1b78eb0e19dcaa'
originals=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE],text=True).splitlines()
for name in originals:
 assert Path(name).read_bytes()==subprocess.check_output(['git','show',f'{BASE}:{name}']), f'Original modified: {name}'
print(f'PASS: {len(originals)} original files byte-identical to V3.1',flush=True)
luau=os.environ.get('LUAU_BIN') or shutil.which('luau')
assert luau, 'Set LUAU_BIN to a Luau CLI executable'
paths=['PCKeyboardTouchBridgeV3.lua','PCRobloxNativeVisualV5.lua','LegacyGridContactAssistV31.lua',
       'LegacyGridContactAssistV31Preserved.lua','CombinedJoystickAssistV31PreservedLoader.lua',
       'PC_Movement_V31_Preserved_AUTOEXECUTE.lua',
       'tests/v31-preserved/RobloxFixture.lua','tests/v31-preserved/Environment.lua']
missing=[p for p in paths if not Path(p).exists()]
assert not missing, 'Preserved V3.1 implementation missing: '+', '.join(missing)
header='local factories={}\n'
for path in paths:
 header+=f'factories[{json.dumps(path)}]=function()\n{Path(path).read_text()}\nend\n'
header+='local function dofile(path) assert(factories[path],path); return factories[path]() end\n'
with tempfile.TemporaryDirectory(prefix='v31-preserved-') as folder:
 for test in sorted(Path('tests/v31-preserved').glob('*_test.lua')):
  harness=Path(folder)/test.name
  harness.write_text(header+test.read_text())
  subprocess.run([luau,str(harness)],check=True)
compiler=os.environ.get('LUAU_COMPILE') or shutil.which('luau-compile')
if compiler:
 # Scope syntax validation to the new modules and original load chain.
 # All-history compilation found unused LegacyProbeV2.lua:225 already invalid;
 # document it and preserve its original bytes instead of altering old projects.
 loaded=['PC_Movement_V31_Preserved_AUTOEXECUTE.lua','CombinedJoystickAssistV31PreservedLoader.lua','LegacyGridContactAssistV31Preserved.lua',
         'PCModeLockV3.lua','PCModeLockV5_7.lua','PCModeLockV5_5.lua','PCModeLockV5_3.lua',
         'PCModeLockV5_2.lua','PCModeLockV5_HUDMobile.lua','PCModeLockV5.lua',
         'ClassicJoystickSelectiveWASD.lua','PCKeyboardTouchBridgeV5_2.lua',
         'PCKeyboardTouchBridgeV3.lua','PCKeyboardControllerWakeV5.lua',
         'CameraTouchRightHalfGateV5.lua','PCRobloxNativeVisualV5.lua']
 files=[str(ROOT/p) for p in loaded]
 subprocess.run([compiler,'--null',*files],check=True)
else:
 print('Luau compile check skipped: set LUAU_COMPILE')
print('PASS: preserved V3.1 suite (offline services; live Delta/game physics still unverified)',flush=True)
