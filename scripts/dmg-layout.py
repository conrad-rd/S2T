"""Write and verify Finder metadata without opening Finder or capturing a screen."""
import base64
import subprocess
import pathlib
import plistlib
import sys
from ds_store import DSStore
from mac_alias import Alias

root = pathlib.Path(sys.argv[1])
background_alias = Alias.for_file(str(root / '.background' / 'install.tiff'))
# Finder resolves the volume identity after mounting; do not substitute a different mount path.
if '--verify' not in sys.argv:
    with DSStore.open(str(root / '.DS_Store'), 'w+') as store:
        store['.']['bwsp'] = dict(ShowStatusBar=False, ShowToolbar=False, ShowSidebar=False,
            ShowPathbar=False, ShowTabView=False, ContainerShowSidebar=False,
            WindowBounds='{{120, 60}, {660, 750}}')
        store['.']['icvp'] = dict(viewOptionsVersion=1, backgroundType=2,
            backgroundImageAlias=background_alias.to_bytes(),
            backgroundColorRed=1.0, backgroundColorGreen=1.0, backgroundColorBlue=1.0,
            scrollPositionX=0.0, scrollPositionY=0.0,
            iconSize=72.0, textSize=11.0, gridSpacing=100.0, gridOffsetX=0.0, gridOffsetY=0.0,
            labelOnBottom=True, showItemInfo=False, showIconPreview=False, arrangeBy='none')
        store['.']['vSrn'] = ('long', 1)
        store['.']['icvl'] = ('type', b'icnv')
        store['.']['vstl'] = ('type', b'icnv')
        store['S2T.app']['Iloc'] = (335, 472)
        store['Applications']['Iloc'] = (330, 164)
with DSStore.open(str(root / '.DS_Store'), 'r') as store:
    assert store['S2T.app']['Iloc'] == (335, 472)
    assert store['Applications']['Iloc'] == (330, 164)
    assert store['.']['icvp']['backgroundType'] == 2
    assert store['.']['icvp']['iconSize'] == 72.0
    assert store['.']['icvl'] == (b'type', b'icnv')
    assert store['.']['vstl'] == (b'type', b'icnv')
    assert store['.']['bwsp']['WindowBounds'] == '{{120, 60}, {660, 750}}'
    saved_alias = Alias.from_bytes(store['.']['icvp']['backgroundImageAlias'])
    with (root / 'S2T.app/Contents/Info.plist').open('rb') as info_file:
        info = plistlib.load(info_file)
    assert saved_alias.volume.name == f"S2T {info['CFBundleShortVersionString']} Build {info['CFBundleVersion']} Layout 7"
    assert saved_alias.target.posix_path == '/.background/install.tiff'
    assert store['.']['bwsp']['ShowToolbar'] is False
subprocess.run(['swift', 'scripts/dmg-applications.swift', str(root / 'Applications'), '--verify'], check=True)
finder_info = bytes.fromhex(subprocess.check_output(['xattr', '-px', 'com.apple.FinderInfo', str(root / 'Applications')], text=True))
assert int.from_bytes(finder_info[8:10], 'big') & 0x8400 == 0x8400
assert subprocess.check_output(['xattr', '-px', 'com.apple.ResourceFork', str(root / 'Applications')]).strip()
assert {p.name for p in root.iterdir() if not p.name.startswith('.')} == {'S2T.app', 'Applications'}
print('DMG layout metadata verified: 660 × 750, app, Applications link, background. No text files.')

subprocess.run(['swift', '-suppress-warnings', 'scripts/verify-dmg-background.swift',
    base64.b64encode(saved_alias.to_bytes()).decode(), str(root / '.background/install.tiff')], check=True)
