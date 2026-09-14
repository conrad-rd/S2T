"""Write and verify Finder metadata without opening Finder or capturing a screen."""
import base64
import subprocess
import pathlib
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
        store['S2T.app']['Iloc'] = (323, 472)
        store['Applications']['Iloc'] = (323, 154)
with DSStore.open(str(root / '.DS_Store'), 'r') as store:
    assert store['S2T.app']['Iloc'] == (323, 472)
    assert store['Applications']['Iloc'] == (323, 154)
    assert store['.']['icvp']['backgroundType'] == 2
    assert store['.']['icvp']['iconSize'] == 72.0
    assert store['.']['icvl'] == (b'type', b'icnv')
    assert store['.']['vstl'] == (b'type', b'icnv')
    assert store['.']['bwsp']['WindowBounds'] == '{{120, 60}, {660, 750}}'
    saved_alias = Alias.from_bytes(store['.']['icvp']['backgroundImageAlias'])
    assert saved_alias.volume.name == 'Install S2T'
    assert saved_alias.target.posix_path == '/.background/install.tiff'
    assert store['.']['bwsp']['ShowToolbar'] is False
assert (root / 'Applications').is_symlink()
assert (root / 'Applications').readlink() == pathlib.Path('/Applications')
assert {p.name for p in root.iterdir() if not p.name.startswith('.')} == {'S2T.app', 'Applications'}
print('DMG layout metadata verified: 660 × 750, app, Applications link, background. No text files.')

subprocess.run(['swift', '-suppress-warnings', 'scripts/verify-dmg-background.swift',
    base64.b64encode(saved_alias.to_bytes()).decode(), str(root / '.background/install.tiff')], check=True)
