import json, os, plistlib, struct, sys, zipfile
from pathlib import Path
path = Path(sys.argv[1])
with zipfile.ZipFile(path) as z:
    assert z.testzip() is None
    info = plistlib.loads(z.read('Payload/AGY.app/Info.plist'))
    assert info['UIDeviceFamily'] == [1], 'Must target iPhone only'
    assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
    assert info['UISupportedInterfaceOrientations'] == ['UIInterfaceOrientationPortrait']
    binary = z.read('Payload/AGY.app/' + info['CFBundleExecutable'])
    assert binary[:4] == b'\xcf\xfa\xed\xfe', 'Expected 64-bit Mach-O'
    assert struct.unpack_from('<I', binary, 4)[0] == 0x100000c, 'Expected arm64'
    commands = struct.unpack_from('<I', binary, 16)[0]
    offset, platform = 32, None
    for _ in range(commands):
        cmd, size = struct.unpack_from('<II', binary, offset)
        if cmd == 0x32: platform = struct.unpack_from('<I', binary, offset+8)[0]
        offset += size
    assert platform == 2, 'Expected physical iOS, not Simulator'
    assert info.get('AGYNativeRendering') in (True, 'YES'), 'Native rendering marker missing'
    assert 'Payload/AGY.app/MobileLayout.js' not in z.namelist(), 'Legacy webpage adapter must not ship'
    assert 'Payload/AGY.app/InboxBridge.js' not in z.namelist(), 'Legacy JavaScript bridge must not ship'
    assert 'Payload/AGY.app/Assets.car' in z.namelist()
    assert info.get('UIFileSharingEnabled') is True, 'Local downloads not exposed in Files'
    assert info.get('LSSupportsOpeningDocumentsInPlace') is True, 'Files document access missing'
    assert info.get('NSSupportsLiveActivities') is True, 'Live Activities support missing'
    extension = 'Payload/AGY.app/PlugIns/AGYLiveActivity.appex/'
    widget = plistlib.loads(z.read(extension + 'Info.plist'))
    assert widget['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.widgetkit-extension'
    assert widget['CFBundleIdentifier'].startswith(info['CFBundleIdentifier'] + '.')
    assert widget['CFBundleShortVersionString'] == info['CFBundleShortVersionString']
    assert widget['CFBundleVersion'] == info['CFBundleVersion']
    widget_binary = z.read(extension + widget['CFBundleExecutable'])
    assert widget_binary[:4] == b'\xcf\xfa\xed\xfe'
    assert struct.unpack_from('<I', widget_binary, 4)[0] == 0x100000c
    assert extension + 'Assets.car' in z.namelist(), 'Official mark missing from Live Activity assets'
manifest = dict(name='AGY', version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'],
                platform='iPhoneOS', architecture='arm64', deviceFamily=info['UIDeviceFamily'],
                sourceCommit=os.environ.get('GITHUB_SHA', 'local'), requiresResigning=True,
                runtimeVerified=False, supportsLiveActivities=True, liveActivityExtension=True, backgroundPush=False)
path.with_name('build-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
print('Verified physical iPhone IPA, arm64, iPhone-only, native rendering, no injected JS, assets, embedded Live Activity extension')
