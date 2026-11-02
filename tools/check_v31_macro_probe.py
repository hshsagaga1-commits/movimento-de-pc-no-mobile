#!/usr/bin/env python3
"""Run the optional macro trace in the existing Roblox fixture and verify scope."""
from pathlib import Path
import json,os,shutil,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[1]
os.chdir(ROOT)
BASE='a48741ca0f7b86f7a2c2631778ee5a86691b180f'
paths=subprocess.check_output(['git','ls-tree','-r','--name-only',BASE],text=True).splitlines()
for p in paths:
 assert Path(p).read_bytes()==subprocess.check_output(['git','show',f'{BASE}:{p}']),f'Base V3.1 file changed: {p}'
print('PASS: every existing V3.1 file byte-identical',flush=True)
header='local factories={}\n'
for path in ['tests/v31-preserved/RobloxFixture.lua','tests/v31-preserved/Environment.lua',
             'PCKeyboardTouchBridgeV3.lua','PCMovementV31MacroConflictProbe.lua',
             'PCMovementV31MacroProbe_AUTOEXECUTE.lua']:
 if Path(path).exists(): header+=f'factories[{json.dumps(path)}]=function()\n{Path(path).read_text()}\nend\n'
header+='local function dofile(path) assert(factories[path], "missing script: "..path);return factories[path]() end\n'
luau=os.environ.get('LUAU_BIN') or shutil.which('luau')
assert luau,'Set LUAU_BIN'
with tempfile.TemporaryDirectory(prefix='v31-macro-probe-tests-') as folder:
 for test in sorted(Path('tests/v31-macro-probe').glob('*_test.lua')):
  p=Path(folder)/test.name
  p.write_text(header+test.read_text())
  subprocess.run([luau,str(p)],check=True)
compiler=os.environ.get('LUAU_COMPILE') or shutil.which('luau-compile')
if compiler:
 sources=['PCMovementV31MacroConflictProbe.lua','PCMovementV31MacroProbe_AUTOEXECUTE.lua']
 subprocess.run([compiler,'--null',*[path for path in sources if Path(path).exists()]],check=True)
print('PASS: optional trace offline, without replacing the input stack',flush=True)
