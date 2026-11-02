#!/usr/bin/env python3
"""Verify V3.1 visual corrections against the user's working base."""
from pathlib import Path
import json,os,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT)
BASE='62269b83bb05f3fd5eca76f5eeb7102555afc241'
changed={'PCKeyboardTouchBridgeV3.lua','PCModeLockV3.lua','CombinedJoystickAssistV31PreservedLoader.lua','PC_Movement_V31_Preserved_AUTOEXECUTE.lua'}
originals=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE],text=True).splitlines()
for p in originals:
 if p not in changed:
  assert Path(p).read_bytes()==subprocess.check_output(['git','show',f'{BASE}:{p}']),f'Unrelated base file changed: {p}'
old_bridge=subprocess.check_output(['git','show',f'{BASE}:PCKeyboardTouchBridgeV3.lua'],text=True)
expected=old_bridge.replace('local maxVisual=math.max(1,movementRadius*0.62)',
 'local maxVisual=math.max(1,math.min(joystick.AbsoluteSize.X,joystick.AbsoluteSize.Y)/2)')
assert expected!=old_bridge
assert Path('PCKeyboardTouchBridgeV3.lua').read_text()==expected,'Bridge changed beyond its single visual radius formula'
old_bootstrap=subprocess.check_output(['git','show',f'{BASE}:PCModeLockV3.lua'],text=True)
expected_bootstrap=old_bootstrap.replace('/feature/pc-movement-assist-v3-20261031/','/feature/pc-movement-v31-ui-fixes-20261102/')
assert Path('PCModeLockV3.lua').read_text()==expected_bootstrap,'PC bootstrap changed beyond the bridge download branch'
print('PASS: single visual bridge edit; all other input/jump code and unrelated base files unchanged',flush=True)
luau=os.environ.get('LUAU_BIN') or shutil.which('luau')
assert luau,'Set LUAU_BIN'
paths=['PCKeyboardTouchBridgeV3.lua','PCRobloxNativeVisualV5.lua','LegacyGridContactAssistV31.lua',
 'LegacyGridContactAssistV31Preserved.lua','CombinedJoystickAssistV31PreservedLoader.lua',
 'PC_Movement_V31_Preserved_AUTOEXECUTE.lua','PCCursorVisualV31.lua',
 'tests/v31-preserved/RobloxFixture.lua','tests/v31-preserved/Environment.lua']
for path in paths: assert Path(path).exists(),f'Missing implementation: {path}'
header='local factories={}\n'
for path in paths: header+=f'factories[{json.dumps(path)}]=function()\n{Path(path).read_text()}\nend\n'
header+='factories["reference/bridge.lua"]=function()\n'+old_bridge+'\nend\n'
header+='local function dofile(path) assert(factories[path],path);return factories[path]() end\n'
tests=[Path('tests/v31-preserved')/name for name in ['assist_test.lua','baseline_test.lua','bridge_test.lua','loader_async_test.lua']]
tests+=sorted(Path('tests/v31-ui').glob('*_test.lua'))
with tempfile.TemporaryDirectory(prefix='v31-ui-tests-') as folder:
 for test in tests:
  p=Path(folder)/test.name;p.write_text(header+test.read_text())
  subprocess.run([luau,str(p)],check=True)
compiler=os.environ.get('LUAU_COMPILE') or shutil.which('luau-compile')
if compiler:
 files=['PCModeLockV3.lua','PCKeyboardTouchBridgeV3.lua','PCRobloxNativeVisualV5.lua','LegacyGridContactAssistV31Preserved.lua',
  'CombinedJoystickAssistV31PreservedLoader.lua','PC_Movement_V31_Preserved_AUTOEXECUTE.lua','PCCursorVisualV31.lua']
 subprocess.run([compiler,'--null',*files],check=True)
print('PASS: visual fixes verified offline; external macro conflict is not declared resolved without its source',flush=True)
