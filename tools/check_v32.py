#!/usr/bin/env python3
"""Check V3.2 changes against the proven V3.1 visual branch with Luau fixtures."""
from pathlib import Path
import json,os,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT)
BASE='a48741ca0f7b86f7a2c2631778ee5a86691b180f'
originals=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE],text=True).splitlines()
for name in originals:
 assert Path(name).read_bytes()==subprocess.check_output(['git','show',f'{BASE}:{name}']),f'Working V3.1 file changed: {name}'
print('PASS: all working V3.1 joystick/keyboard/camera/Assist files preserved byte-for-byte',flush=True)
luau=os.environ.get('LUAU_BIN') or shutil.which('luau')
assert luau,'Set LUAU_BIN'
paths=['tests/v31-preserved/RobloxFixture.lua','tests/v31-preserved/Environment.lua']
assist='LegacyGridContactAssistV32.lua' if Path('LegacyGridContactAssistV32.lua').exists() else 'LegacyGridContactAssistV31Preserved.lua'
paths.append(assist)
loader='CombinedJoystickAssistV32Loader.lua' if Path('CombinedJoystickAssistV32Loader.lua').exists() else 'CombinedJoystickAssistV31PreservedLoader.lua'
wrapper='PC_Movement_V32_AUTOEXECUTE.lua' if Path('PC_Movement_V32_AUTOEXECUTE.lua').exists() else 'PC_Movement_V31_Preserved_AUTOEXECUTE.lua'
paths.extend([loader,wrapper,'PCCursorVisualV31.lua'])
header='local factories={}\n'
for path in paths:
 header+=f'factories[{json.dumps(path)}]=function()\n{Path(path).read_text()}\nend\n'
header+=f'factories["LegacyGridContactAssistV32.lua"]=factories[{json.dumps(assist)}]\n'
header+=f'factories["CombinedJoystickAssistV32Loader.lua"]=factories[{json.dumps(loader)}]\n'
header+=f'factories["PC_Movement_V32_AUTOEXECUTE.lua"]=factories[{json.dumps(wrapper)}]\n'
header+='local function dofile(path) assert(factories[path],path);return factories[path]() end\n'
with tempfile.TemporaryDirectory(prefix='v32-tests-') as folder:
 for name in ['assist_test.lua','loader_test.lua']:
  p=Path(folder)/name;p.write_text(header+(Path('tests/v32')/name).read_text())
  subprocess.run([luau,str(p)],check=True)
 p=Path(folder)/'assist_regression.lua'
 baseline=Path('tests/v31-preserved/assist_test.lua').read_text().replace(
  "dofile('LegacyGridContactAssistV31Preserved.lua')","dofile('LegacyGridContactAssistV32.lua')")
 p.write_text(header+baseline)
 subprocess.run([luau,str(p)],check=True)
compiler=os.environ.get('LUAU_COMPILE') or shutil.which('luau-compile')
if compiler and Path('CombinedJoystickAssistV32Loader.lua').exists():
 subprocess.run([compiler,'--null','LegacyGridContactAssistV32.lua',
  'CombinedJoystickAssistV32Loader.lua','PC_Movement_V32_AUTOEXECUTE.lua'],check=True)
print('PASS: V3.2 isolated assist and loader syntax (physics still requires Delta/Evade)',flush=True)
