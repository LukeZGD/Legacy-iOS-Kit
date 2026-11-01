#!/usr/bin/env python3
"""Build the bundled ARMv7 diagnostics on macOS. End users use the pinned tar.

Requires Apple's command-line tools (including ld-classic) and an iPhoneOS
10.3 SDK. The SDK is never included in the distribution. No phone is contacted.
"""
import argparse
import hashlib
import io
import json
from pathlib import Path
import plistlib
import re
import shutil
import struct
import subprocess
import tarfile
import zlib

HERE = Path(__file__).resolve().parent
ASSETS = HERE.parent / 'assets'
LABEL = 'org.legacyioskit.ios10.diagnostics'
DEVICE = 'usr/local/share/lik-ios10'
APP = 'Applications/LIKTools.app'

def run(*args):
    subprocess.run([str(a) for a in args], check=True)

def png(size):
    # A simple, original pixel icon; no external artwork or fonts.
    glyphs = ['01001110', '11001010', '01001010', '01001010', '11101110']
    scale = max(1, size // 12)
    left, top = (size-8*scale)//2, (size-5*scale)//2
    pixels = bytearray()
    for y in range(size):
        pixels.append(0)
        for x in range(size):
            gx, gy = (x-left)//scale, (y-top)//scale
            white = 0 <= gx < 8 and 0 <= gy < 5 and glyphs[gy][gx] == '1'
            pixels.extend((255,255,255) if white else (17,105,120))
    def chunk(kind, data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(pixels,9))+chunk(b'IEND',b'')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sdk',type=Path,required=True)
    parser.add_argument('--build-dir',type=Path,required=True)
    args=parser.parse_args()
    sdk=args.sdk.resolve(); build=args.build_dir.resolve()
    if not (sdk/'SDKSettings.plist').is_file():
        parser.error('Supply the extracted iPhoneOS10.3.sdk directory')
    build.mkdir(parents=True,exist_ok=True)
    # Work around old merged device/simulator TBD metadata in a build-local
    # copy only. Upstream documents this issue at theos/sdks#56.
    link_sdk=build/'link-sdk'
    if link_sdk.exists(): shutil.rmtree(link_sdk)
    for stub in sdk.rglob('*.tbd'):
        target=link_sdk/stub.relative_to(sdk);target.parent.mkdir(parents=True,exist_ok=True)
        text=stub.read_text()
        text=re.sub(r'^archs:.*$', 'archs: [ armv7, armv7s, arm64 ]',text,flags=re.M)
        # The merged 10.3 stubs omit these standard libc resolver exports.
        # Only the link description changes; the installed device supplies
        # libSystem. No replacement system library is built or bundled.
        if str(stub.relative_to(sdk))=='usr/lib/libSystem.tbd':
            text=text.replace('symbols:            [ ', 'symbols:            [ _memcmp, _memset, _strcmp, ',1)
        target.write_text(text)
    clang=subprocess.check_output(['xcrun','--find','clang'],text=True).strip()
    ld=Path(clang).parent/'ld-classic'
    if not ld.is_file(): parser.error('The ARMv7-capable Apple ld-classic is required')
    for source in ('Diagnostics','Installer','SSH','Helper','App'):
        run(clang,'-target','armv7-apple-ios10.0','-isysroot',sdk,'-fobjc-arc','-fblocks','-Os',
            '-Wall','-Wextra','-Werror','-Wno-unused-parameter','-c',HERE/(source+'.m'),'-o',build/(source+'.o'))
    app=build/'LIKTools.app'
    if app.exists(): shutil.rmtree(app)
    app.mkdir()
    for target,source,frameworks in ((build/'diagnostic-helper','Helper',('MobileCoreServices',)),(app/'LIKTools','App',('UIKit',))):
        command=[ld,'-arch','armv7','-iphoneos_version_min','10.0','-syslibroot',link_sdk,'-no_uuid',
                 '-lSystem','-lobjc','-framework','Foundation','-framework','CoreFoundation']
        for fw in frameworks: command += ['-framework',fw]
        objects=[build/'Diagnostics.o',build/(source+'.o')]
        if source=='Helper': objects += [build/'Installer.o',build/'SSH.o']
        run(*command,*objects,'-o',target)
    icons=[]
    for name,size in (('Icon60@2x',120),('Icon76',76),('Icon76@2x',152),('Icon83.5@2x',167)):
        (app/(name+'.png')).write_bytes(png(size)); icons.append(name)
    info=dict(CFBundleIdentifier='org.legacyioskit.custom.ios10tools',CFBundleName='LIKTools',
              CFBundleDisplayName='iOS 10 Tools',CFBundleExecutable='LIKTools',CFBundlePackageType='APPL',
              CFBundleVersion='9',CFBundleShortVersionString='0.9',MinimumOSVersion='10.0',
              LSRequiresIPhoneOS=True,UIDeviceFamily=[1,2],UIRequiredDeviceCapabilities=['armv7'],
              CFBundleIconFiles=icons,UILaunchImages=[dict(UILaunchImageName='Launch',UILaunchImageSize='{320, 568}',UILaunchImageOrientation='Portrait',UILaunchImageMinimumOSVersion='7.0')],
              UISupportedInterfaceOrientations=['UIInterfaceOrientationPortrait','UIInterfaceOrientationLandscapeLeft','UIInterfaceOrientationLandscapeRight'])
    # Explicit iPhone 5 launch size prevents the old 3.5-inch compatibility mode.
    (app/'Default-568h@2x.png').write_bytes(png_rect(640,1136))
    info.pop('UILaunchImages')
    (app/'Info.plist').write_bytes(plistlib.dumps(info))
    entitlements=build/'entitlements.plist'
    entitlements.write_bytes(plistlib.dumps({'platform-application':True,'com.apple.private.security.no-container':True,'get-task-allow':True}))
    for target in (build/'diagnostic-helper',app):
        run('/usr/bin/codesign','--force','--sign','-','--timestamp=none','--digest-algorithm=sha1,sha256',
            '--identifier','org.legacyioskit.custom.'+target.stem,'--entitlements',entitlements,target)
        run('/usr/bin/codesign','--verify','--strict',target)
    files={}
    for path in sorted(app.rglob('*')):
        if path.is_file(): files[APP+'/'+str(path.relative_to(app))]=(path.read_bytes(),0o755 if path.name=='LIKTools' else 0o644)
    files[DEVICE+'/diagnostic-helper']=((build/'diagnostic-helper').read_bytes(),0o755)
    daemon=dict(Label=LABEL,ProgramArguments=['/'+DEVICE+'/diagnostic-helper'],RunAtLoad=True,
                KeepAlive={'SuccessfulExit':False},ThrottleInterval=15,UserName='root',
                StandardOutPath='/var/log/lik-ios10-diagnostics.log',StandardErrorPath='/var/log/lik-ios10-diagnostics.log')
    files['System/Library/LaunchDaemons/'+LABEL+'.plist']=(plistlib.dumps(daemon),0o644)
    archive=ASSETS/'diagnostics.tar'
    with tarfile.open(archive,'w',format=tarfile.GNU_FORMAT) as tar:
        # stage.py creates all parent directories in the complete staging tar.
        for name,(data,mode) in sorted(files.items()):
            entry=tarfile.TarInfo(name);entry.mode=mode;entry.size=len(data)
            tar.addfile(entry,io.BytesIO(data))
    meta=dict(architecture='armv7',minimum_ios='10.0',sdk='iPhoneOS10.3',
              sdk_archive_sha256='bc32f1dd2a7a474bc3c74c225d2b3ad182f56f1cd1c9a432c39e83d0555acc0c',
              link_stub_adjustments='Build-local device-only TBD headers and missing standard libSystem resolver declarations: memcmp, memset, strcmp',
              sdk_source='https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS10.3.sdk.tar.xz',
              compiler=subprocess.check_output([clang,'--version'],text=True).splitlines()[0],
              source_sha256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(HERE.iterdir()) if p.suffix in ('.m','.h','.py')},
              files_sha256={n:hashlib.sha256(v[0]).hexdigest() for n,v in files.items()},
              source='../diagnostics',builder='../diagnostics/build.py',hardware_tested=False)
    (ASSETS/'diagnostics-build.json').write_text(json.dumps(meta,indent=2,sort_keys=True)+'\n')
    manifest_path=ASSETS/'manifest.json'; manifest=json.loads(manifest_path.read_text())
    for name in ('diagnostics.tar','diagnostics-build.json'):
        manifest['sha256'][name]=hashlib.sha256((ASSETS/name).read_bytes()).hexdigest()
    manifest['diagnostics']=dict(build='ios10-dev.9',source='../diagnostics',hardware_tested=False)
    manifest_path.write_text(json.dumps(manifest,indent=2)+'\n')
    print('Built and signed ARMv7 app/helper; no device contacted. Hardware launch remains unverified.')

def png_rect(width,height):
    def chunk(kind,data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    data=(b'\0'+bytes((17,105,120))*width)*height
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(data,9))+chunk(b'IEND',b'')

if __name__=='__main__':main()
