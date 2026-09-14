"""Write and verify Finder metadata without opening Finder or capturing a screen."""
import pathlib
import sys
from ds_store import DSStore
from mac_alias import Alias

root = pathlib.Path(sys.argv[1])
background_alias = Alias.for_file(str(root / '.background' / 'install.tiff'))
# The mounted image's local build path must not travel with the installer.
background_alias.volume.posix_path = '/Volumes/S2T'
with DSStore.open(str(root / '.DS_Store'), 'w+') as store:
    store['.']['bwsp'] = dict(ShowStatusBar=False, ShowToolbar=False, ShowSidebar=False,
        ShowPathbar=False, ShowTabView=False, ContainerShowSidebar=False,
        WindowBounds='{{180, 160}, {660, 460}}')
    store['.']['icvp'] = dict(viewOptionsVersion=1, backgroundType=2,
        backgroundImageAlias=background_alias.to_bytes(),
        iconSize=88.0, textSize=14.0, gridSpacing=100.0, gridOffsetX=0.0, gridOffsetY=0.0,
        labelOnBottom=True, showItemInfo=False, showIconPreview=False, arrangeBy='none')
    store['.']['vSrn'] = ('long', 1)
    store['.']['icvl'] = ('type', b'icnv')
    store['S2T.app']['Iloc'] = (179, 220)
    store['Applications']['Iloc'] = (477, 220)
with DSStore.open(str(root / '.DS_Store'), 'r') as store:
    assert store['S2T.app']['Iloc'] == (179, 220)
    assert store['Applications']['Iloc'] == (477, 220)
    assert store['.']['icvp']['backgroundType'] == 2
    saved_alias = Alias.from_bytes(store['.']['icvp']['backgroundImageAlias'])
    assert saved_alias.volume.posix_path == '/Volumes/S2T'
    assert saved_alias.target.posix_path == '/.background/install.tiff'
    assert store['.']['bwsp']['ShowToolbar'] is False
assert (root / 'Applications').is_symlink()
assert (root / 'Applications').readlink() == pathlib.Path('/Applications')
assert {p.name for p in root.iterdir() if not p.name.startswith('.')} == {'S2T.app', 'Applications'}
print('DMG layout metadata verified: 660 × 460, app, Applications link, background. No text files.')
