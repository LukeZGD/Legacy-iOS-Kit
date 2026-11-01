#!/usr/bin/env python3
"""Split pinned Socket packages into system files and a late-restore data plan."""
import argparse, copy, hashlib, io, json, os, plistlib, re, tarfile, uuid
from pathlib import Path, PurePosixPath
from macho import ImageError
from prepare import digest, validate_target, write_json
HERE=Path(__file__).resolve().parent
PREFIX='usr/local/share/lik-aio'

def name(path):
    path=path[2:] if path.startswith('./') else path
    path=path.rstrip('/')
    if path in ('','.'):return ''
    if path.startswith('/') or '..' in PurePosixPath(path).parts:raise ImageError('Unsafe package path')
    return path

def read_tar(data):
    result={}
    with tarfile.open(fileobj=io.BytesIO(data)) as t:
        for m in t:
            n=name(m.name)
            if not n:continue
            if n in result:raise ImageError('Duplicate package path: '+n)
            if not (m.isfile() or m.isdir() or m.issym() or m.islnk()):raise ImageError('Unsupported package entry')
            result[n]=(copy.copy(m),t.extractfile(m).read() if m.isfile() else b'')
    for n,(m,d) in list(result.items()):
        if m.islnk():
            target=name(m.linkname)
            if target not in result or not result[target][0].isfile():raise ImageError('Invalid package hard link')
            m.type=tarfile.REGTYPE;m.linkname='';result[n]=(m,result[target][1])
    return result

def deb(path):
    data=path.read_bytes()
    if not data.startswith(b'!<arch>\n'):raise ImageError('Invalid Debian archive')
    pos=8;parts={}
    while pos<len(data):
        h=data[pos:pos+60]
        if len(h)!=60 or h[58:]!=b'`\n':raise ImageError('Invalid ar header')
        size=int(h[48:58]);key=h[:16].decode().strip().rstrip('/')
        parts[key]=data[pos+60:pos+60+size];pos+=60+size+(size%2)
    def one(prefix):
        matches=[v for k,v in parts.items() if k.startswith(prefix)]
        if len(matches)!=1:raise ImageError('Ambiguous package member')
        return read_tar(matches[0])
    return one('control.tar'),one('data.tar')

def file_entry(data,mode=0o644,uid=0,gid=0):
    m=tarfile.TarInfo();m.mode=mode;m.uid=uid;m.gid=gid;m.size=len(data);return m,data

def add(files,path,data=b'',mode=0o644,uid=0,gid=0):files[path]=file_entry(data,mode,uid,gid)

def bootstrap_status(files):
    """Complete installed-package records only when their listed payload exists."""
    result=[];seen=set()
    for entry in re.split(r'\n\n+', files['private/var/lib/dpkg/status'][1].decode().strip()):
        package=re.findall(r'^Package: (.+)$',entry,re.M)
        if len(package)!=1 or package[0] in seen:raise ImageError('Invalid bootstrap package record')
        package=package[0];seen.add(package)
        if not re.search(r'^Status:',entry,re.M):
            listing=files.get('private/var/lib/dpkg/info/'+package+'.list')
            if not listing:raise ImageError('Missing installed file list for '+package)
            payload=[n.lstrip('/') for n in listing[1].decode().splitlines() if n not in ('','/.','/')]
            if not payload or any(n not in files for n in payload):
                raise ImageError('Incomplete installed payload for '+package)
            if not any(files[n][0].isfile() for n in payload):
                raise ImageError('No installed payload files for '+package)
            entry+='\nStatus: install ok installed'
        result.append(entry)
    return '\n\n'.join(result)+'\n\n'


def configure_startup(files):
    # Keep Socket's bootstrap startup (including AutoInstall) as the ONLY
    # metadata owner. firmware.sh removes other status-tmp files, so a second
    # launch daemon calling it can destroy the first job's pending database.
    path='usr/libexec/cydia/startup';m,data=files[path];text=data.decode()
    call='/usr/libexec/cydia/firmware.sh'
    if text.count(call)!=1:raise ImageError('Unexpected bootstrap startup script')
    text=text.replace(call,call+' || exit $?')
    text=text.rstrip()+'\n\n# Record completion only after firmware metadata succeeded.\n/'+PREFIX+'/metadata.sh\n'
    files[path]=(m,text.encode())
    path='Library/LaunchDaemons/com.saurik.Cydia.Startup.plist'
    job=plistlib.loads(files[path][1])
    job.update(StandardOutPath='/var/log/lik-ios10-metadata.log',StandardErrorPath='/var/log/lik-ios10-metadata.log')
    add(files,path,plistlib.dumps(job))


def compose(info):
    assets=HERE/'assets';manifest=json.loads((assets/'manifest.json').read_text())
    required=('bootstrap.tar','tar','launchctl','zebra.deb','procyon.deb','allinone-nvram','allinone-lik-restore-finalize','allinone-build.json')
    for n in required:
        if digest(assets/n)!=manifest['sha256'][n]:raise ImageError('Pinned asset changed: '+n)
    build=json.loads((assets/'allinone-build.json').read_text())
    for n,sha in build['source_sha256'].items():
        if digest(HERE/'allinone'/n)!=sha:raise ImageError('Rebuild the native finalizer after changing '+n)
    files=read_tar((assets/'bootstrap.tar').read_bytes())
    files={n:v for n,v in files.items() if not (v[0].isdir() and (n=='System' or n.startswith('System/')))}
    # No Cydia application. Socket uses this bootstrap's command-line plumbing.
    if any(n.startswith('Applications/Cydia.app') for n in files):raise ImageError('Unexpected Cydia application')
    status=bootstrap_status(files)
    for package in ('zebra.deb','procyon.deb'):
        control,payload=deb(assets/package);text=control['control'][1].decode()
        pkg=re.search(r'^Package: (.+)$',text,re.M).group(1)
        files.update(payload)
        for n,(m,d) in control.items():
            if n=='control' or not m.isfile():continue
            files['private/var/lib/dpkg/info/'+pkg+'.'+n]=(m,d)
        listing='/.\n'+''.join('/'+n+'\n' for n in sorted(payload))
        add(files,'private/var/lib/dpkg/info/'+pkg+'.list',listing.encode())
        status+=text.rstrip()+'\nStatus: install ok installed\n\n'
    # Zebra v1.1.36 postinst: iOS <13 uses a root-owned 06755 supersling;
    # iOS <11 also registers the sileo URL scheme. Match those effects offline.
    m,d=files['Applications/Zebra.app/supersling'];m.mode=0o6755;m.uid=m.gid=0
    p='Applications/Zebra.app/Info.plist';z=plistlib.loads(files[p][1])
    schemes=z['CFBundleURLTypes'][0]['CFBundleURLSchemes']
    if 'sileo' not in schemes:schemes.append('sileo')
    add(files,p,plistlib.dumps(z))
    # Socket repairs these fat helpers before installing its bootstrap.
    for n in ('tar','launchctl'):
        # Socket copies the helpers BEFORE extraction; the bootstrap's tar
        # supersedes the initial extraction helper when the archive provides it.
        if 'bin/'+n not in files:add(files,'bin/'+n,(assets/n).read_bytes(),0o755)
    for n in ('.installed_socket','.cydia_no_stash'):add(files,n)
    # Supply the basic firmware dependency immediately. The normal post-boot
    # metadata refresh below generates GraphicsServices virtual dependencies.
    status+=('Package: firmware\nEssential: yes\nStatus: install ok installed\nPriority: required\nSection: System\n'
             'Architecture: iphoneos-arm\nVersion: '+info['version']+'\nDescription: iOS firmware\nName: iOS Firmware\n\n')
    add(files,'private/var/lib/dpkg/status',status.encode())
    sources=('deb http://apt.saurik.com/ ios/1349.70 main\n'
             'deb http://apt.thebigboss.org/repofiles/cydia/ stable main\n'
             'deb http://modmyi.saurik.com/ stable main\ndeb https://repo.chariz.com/ ./\n'
             'deb https://repo.packix.com/ ./\ndeb https://havoc.app/ ./\n'
             'deb https://getzbra.com/repo ./\ndeb https://lukezgd.github.io/repo ./\n')
    add(files,'private/var/mobile/Library/Application Support/xyz.willy.Zebra/sources.list',sources.encode(),uid=501,gid=501)
    add(files,PREFIX+'/metadata.sh',(HERE/'allinone/metadata.sh').read_bytes(),0o755)
    configure_startup(files)
    add(files,PREFIX+'/Procyon-LICENSE',(HERE/'allinone/Procyon-LICENSE').read_bytes())
    add(files,PREFIX+'/Socket-LICENSE',(assets/'Socket-LICENSE').read_bytes())
    for n in list(files):
        if n.startswith('private/var/'):
            for parent in PurePosixPath(n).parents:
                parent=str(parent)
                if not parent.startswith('private/var/') or parent in files:continue
                m=tarfile.TarInfo(parent);m.type=tarfile.DIRTYPE;m.mode=0o755
                if parent=='private/var/mobile' or parent.startswith('private/var/mobile/'):m.uid=m.gid=501
                files[parent]=(m,b'')
    system={};plan=dict(schema=1,product=info['product'],board=info['board'],version=info['version'],build=info['build'],session=info['session'],data=[],final_data=[])
    # Parent metadata is only applied when a directory is NEW on the device.
    for n,(m,d) in sorted(files.items(),key=lambda it:(it[0].count('/'),it[0])):
        if n=='private/var':continue
        if n.startswith('private/var/') or n.startswith('var/'):
            rel=n.split('var/',1)[1]
            e=dict(path=rel,mode=m.mode,uid=m.uid,gid=m.gid)
            if m.isdir():e['kind']='dir'
            elif m.issym():e.update(kind='link',link=m.linkname)
            else:
                blob=str(len(plan['data'])+len(plan['final_data']));e.update(kind='file',blob=blob,sha256=hashlib.sha256(d).hexdigest())
                add(system,PREFIX+'/data/'+blob,d,0o600)
            plan['final_data' if rel=='lib/dpkg/status' else 'data'].append(e)
        else:system[n]=(m,d)
    add(system,PREFIX+'/plan.plist',plistlib.dumps(plan))
    return system,manifest

def write_tar(path,entries):
    # Parents first, deterministic GNU headers accepted by Kit's HFS tool.
    entries=dict(entries)
    for n in list(entries):
        for p in PurePosixPath(n).parents:
            if str(p)=='.':continue
            if str(p) not in entries:
                m=tarfile.TarInfo(str(p));m.type=tarfile.DIRTYPE;m.mode=0o755;entries[str(p)]=(m,b'')
    with tarfile.open(path,'w',format=tarfile.GNU_FORMAT) as t:
        for n,(m,d) in sorted(entries.items(),key=lambda it:(it[0].count('/'),it[0])):
            m=copy.copy(m);m.name=('./'+n if len(n.encode('utf-8')) in (99,100) else n)
            # xpwn's reader expects a NUL in the 100-byte name field. Force
            # GNU LongLink for boundary-length names (and directory slashes).
            m.mtime=0;m.uname=m.gname='';m.size=len(d) if m.isfile() else 0
            t.addfile(m,io.BytesIO(d) if m.isfile() else None)

def create_session(directory,product,board,version,build,ecid):
    validate_target(product,board,version,build)
    if not re.fullmatch('[1-9][0-9]{0,19}',ecid) or int(ecid)>=2**64:raise ImageError('Invalid ECID')
    directory=Path(directory);directory.mkdir(mode=0o700)
    info=dict(schema=1,session=str(uuid.uuid4()),product=product,board=board,version=version,build=build,ecid=ecid)
    files,manifest=compose(info);write_tar(directory/'stage.tar',files)
    info.update(phase='staged',stage_sha256=digest(directory/'stage.tar'),installer='restore-allinone',assets_sha256=manifest['sha256'],hardware_tested=False)
    write_json(directory/'session.json',info);return info

def main():
    p=argparse.ArgumentParser(description=__doc__)
    for n in ('directory','product','board','version','build','ecid'):p.add_argument('--'+n,required=True)
    a=p.parse_args();create_session(**vars(a));print('Prepared all-in-one restore assets.')
if __name__=='__main__':main()
