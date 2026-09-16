#!/usr/bin/env python3
"""Execute the production V614 report-chunk helpers with the Luau CLI."""

from __future__ import annotations

import os
from pathlib import Path
import re
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent
RUNTIME = ROOT / "PCMovementV614_ControlledYawPitchMatching.lua"
LOADER = ROOT / "Loader.lua"
START = "-- BEGIN V614 REPORT TRANSPORT PURE HELPERS"
END = "-- END V614 REPORT TRANSPORT PURE HELPERS"


def luau_binary() -> Path:
    configured = os.environ.get("LUAU_BIN")
    if configured:
        return Path(configured)
    return ROOT.parent / "tooling" / "luau-bin" / "luau"


source = RUNTIME.read_text(encoding="utf-8")
loader_source = LOADER.read_text(encoding="utf-8")
if 'local revision="V614-TemporalPoseTelemetryR1-ChunkExportR1"' not in loader_source:
    raise SystemExit("RED: Loader cache revision was not updated for ChunkExportR1")
match = re.search(re.escape(START) + r"\n(.*?)\n" + re.escape(END), source, re.S)
if not match:
    raise SystemExit("RED: production report-transport helper block is missing")

required_mobile_export_fragments = (
    'SEGCFG.exportCopyButton=makeButton(body,"GERAR PARTES DO REPORT"',
    'SEGCFG.exportPreviousButton=makeButton(body,"PARTE ANTERIOR"',
    'SEGCFG.exportNextButton=makeButton(body,"PRÓXIMA PARTE"',
    "copyToClipboard(transport.text)",
    "reportId=%s",
    "SEGCFG.resetReportExport()",
)
missing = [fragment for fragment in required_mobile_export_fragments if fragment not in source]
if missing:
    raise SystemExit("RED: mobile chunk exporter is incomplete: " + " | ".join(missing))

test_program = (
    "local SEGCFG={}\n"
    + match.group(1)
    + r'''
local function expect(condition,message)
    if not condition then error(message,0) end
end

local function verifyCase(name,report,maxPayload,expectedParts)
    local chunks=SEGCFG.splitReportPayloads(report,maxPayload)
    expect(#chunks==expectedParts,name..": part count")
    expect(table.concat(chunks)==report,name..": exact reconstruction")
    for index,payload in ipairs(chunks) do
        expect(SEGCFG.reportCharCount(payload)<=maxPayload,name..": payload limit")
        local wrapped=SEGCFG.makeReportChunkTransport(
            "11111111-2222-3333-4444-555555555555",
            SEGCFG.reportCharCount(report),chunks,index,30000
        )
        expect(type(wrapped)=="table",name..": envelope missing")
        expect(wrapped.transportChars<=30000,name..": transport limit")
        expect(wrapped.payloadChars==SEGCFG.reportCharCount(payload),name..": payload count")
        expect(string.sub(wrapped.text,wrapped.payloadStartByte,wrapped.payloadEndByte)==payload,
            name..": envelope changed payload")
        expect(string.find(wrapped.text,"reportId = 11111111-2222-3333-4444-555555555555",1,true)~=nil,
            name..": reportId missing")
        expect(string.find(wrapped.text,"=== END CHUNK",1,true)~=nil,name..": end marker missing")
    end
end

verifyCase("empty","",29500,1)
verifyCase("exact",string.rep("a",29500),29500,1)
verifyCase("over",string.rep("b",29501),29500,2)
verifyCase("three",string.rep("c",60001),29500,3)
verifyCase("utf8",string.rep("á🙂漢字\n",10000),29500,2)
verifyCase("raw-markers","\n=== raw ===\nline\n\n=== END-looking text ===\n",29500,1)

local original="á🙂A\nB漢字"..string.rep("z",70000).."\nFIM\n"
local chunks=SEGCFG.splitReportPayloads(original,29500)
expect(table.concat(chunks)==original,"final byte-for-byte reconstruction")
print("PASS: V614 report transport preserves the exact original report")
'''
)

with tempfile.TemporaryDirectory(prefix="v614-chunk-test-") as temp_dir:
    test_path = Path(temp_dir) / "chunk_test.luau"
    test_path.write_text(test_program, encoding="utf-8")
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
