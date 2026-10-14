#!/usr/bin/env python3
"""Compile production Luau and run the actual core against deterministic Roblox mocks."""
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
for command in ('luau', 'luau-compile'):
    if not shutil.which(command):
        raise SystemExit(f'{command} is required (https://github.com/luau-lang/luau).')
subprocess.run(['luau-compile', str(root / 'main.lua')], stdout=subprocess.DEVNULL, check=True)
source = (root / 'main.lua').read_text()
core = source[:source.index('-- UI HELPERS')]
# Preserve the production functions and local variable scope; only expose test hooks.
exports = '''
return {
    cfg=Cfg, providers=PROVIDERS, runtime=Runtime, normalize=NormalizeCfg, save=SaveCfg, load=LoadCfg,
    history=History, privateHistory=PrivateHistory, saveMemory=SaveMemory, cleanHistory=CleanHistory,
    truncate=Truncate, parse=ParseAIText, allowed=IsPlayerAllowed, request=DoRequest,
    generic=GenericCall, raw=RawCall, messages=BuildMsgs, enqueue=Enqueue, queue=MsgQueue,
    clear=ClearMemory, enable=SetEnabled, model=SetModel, send=SendChat, export=ExportChatLog,
    busy=function() return ProcessingMsg end,
    billboard=UpdateBillboard, billboardState=Billboard, speech=Speech,
    resolveEndpoints=ResolveCustomEndpoints, parseModels=ParseModelList, discover=DiscoverModels,
    base64=EncodeBase64, avatarImage=GetAvatarImageData, checkTools=CheckAvatarToolSupport, toolSupport=AvatarToolSupport,
    customVisionSettings=GetCustomVisionSettings, describeAvatar=DescribeCustomAvatar,
    clearVision=ClearVisionCache, visionCache=VisionCache,
}
'''
fixture = (root / 'tests' / 'runtime.luau').read_text()
fixture = fixture.replace('-- INSERT_PRODUCTION_CORE', 'local function boot()\n' + core + exports + '\nend')
with tempfile.TemporaryDirectory(prefix='aibot-tests-') as directory:
    generated = Path(directory) / 'runtime.luau'
    generated.write_text(fixture)
    subprocess.run(['luau', str(generated)], check=True)

# Exercise the entire wizard and panel with simulated Roblox GUI objects.
preamble = (root / 'tests' / 'runtime.luau').read_text().split('-- INSERT_PRODUCTION_CORE')[0]
ui = preamble + (root / 'tests' / 'ui.luau').read_text()
ui = ui.replace('-- INSERT_FULL_SCRIPT', 'local function bootUI()\n' + source + exports + '\nend')
with tempfile.TemporaryDirectory(prefix='aibot-ui-tests-') as directory:
    generated = Path(directory) / 'ui.luau'
    generated.write_text(ui)
    subprocess.run(['luau', str(generated)], check=True)
