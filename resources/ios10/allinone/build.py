#!/usr/bin/env python3
"""Build restore-only ARMv7 programs. Distribution uses the pinned binaries."""
import argparse, hashlib, json, re, shutil, subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent

def run(*args): subprocess.run(list(map(str,args)),check=True)
def replace_once(text,old,new):
    if text.count(old)!=1: raise ValueError('Upstream adaptation no longer matches: '+old[:80])
    return text.replace(old,new)
def adapt(build):
    source=build/'source';shutil.copytree(HERE/'upstream/procyon',source,dirs_exist_ok=True)
    common=source/'include/common.h'
    common.write_text(common.read_text().replace('#endif /* procyon_common_h */','#include "pathmap.h"\n#endif /* procyon_common_h */'))
    path=source/'src/util.c';s=path.read_text()
    start=s.index('void get_ios_version(');end=s.index('\nvoid print_log',start)
    s=s[:start]+'extern void lik_target_version(uint32_t *);\nvoid get_ios_version(uint32_t *output) { lik_target_version(output); }\n'+s[end:]
    s=replace_once(s,'open(to, O_RDWR|O_CREAT);','open(to, O_RDWR|O_CREAT|O_TRUNC, st.st_mode & 07777);')
    s=replace_once(s,'if (access(path, F_OK) != 0) return 0;',
        'struct stat probe = {0}; if (lstat(path, &probe) != 0) return errno == ENOENT ? 0 : -1;')
    s=replace_once(s,'if (access(to, F_OK) == 0) {','struct stat probe = {0}; if (lstat(to, &probe) == 0) {')
    path.write_text(s)
    path=source/'src/dyld_cache.c';s=path.read_text()
    start=s.index('__attribute__((naked))');end=s.index('dsc_info_t *dyld_cache_init',start);s=s[:start]+s[end:]
    start=s.index('    if (hdr == NULL) {');end=s.index('\n    dsc_info_t *dsc_info',start)
    s=s[:start]+'    if (hdr == NULL) return NULL; // Never use the ramdisk process cache.\n'+s[end:]
    start=s.index('    task_dyld_info_data_t');end=s.index('\n    if (dsc_info->mapped)',start)
    s=s[:start]+'    dsc_info->slide = 0; // File addresses are unslid; repair words are decoded separately.\n'+s[end:]
    s=replace_once(s,'dsc_info->images[i].size = image_info[i+1].address - image_info[i].address;',
        'dsc_info->images[i].size = (i+1 < dsc_info->image_count) ? image_info[i+1].address - image_info[i].address : 0;')
    path.write_text(s)
    path=source/'src/stage2.c';s=path.read_text()
    s=replace_once(s,'#include "procyon.h"','#include "procyon.h"\n#include "cache_rebase.h"')
    s=replace_once(s,'static void rop_repair_data(void) {','static int rop_repair_data(void) {')
    start=s.index('            uint32_t value = *(uint32_t *)(procyon->stage2.repair_local')
    end=s.index('\n        }',start)
    s=s[:start]+'''            uint32_t dest = procyon->stage2.repair_start + procyon->stage2.repair_offset + offset;
            uint32_t value = 0;
            int is_pointer = 0;
            if (lik_cache_word(procyon->dsc.info->hdr, procyon->dsc.info->size,
                               dest, &value, &is_pointer) != 0) {
                print_log(true, "[-] Cannot decode dyld cache repair word at 0x%x\\n", dest);
                return -1;
            }
            rop_slide_write32(dest, value, is_pointer != 0);'''+s[end:]
    s=replace_once(s,'\n}\n\nint gen_stage2(void)', '\n    return 0;\n}\n\nint gen_stage2(void)')
    s=replace_once(s,'    rop_repair_data();','''    if (rop_repair_data() != 0) {
        free(stage2_data);
        stage2_data = NULL;
        close(fd);
        return -1;
    }''')
    path.write_text(s)
    path=source/'src/stage3.c'
    path.write_text(replace_once(path.read_text(),'pid_cvm_map_protectheck:','vm_map_protect:'))
    return source

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--sdk',type=Path,required=True);p.add_argument('--build-dir',type=Path,required=True);a=p.parse_args()
    build=a.build_dir.resolve();build.mkdir(parents=True,exist_ok=True);sdk=a.sdk.resolve();link=build/'link-sdk'
    for stub in sdk.rglob('*.tbd'):
        out=link/stub.relative_to(sdk);out.parent.mkdir(parents=True,exist_ok=True)
        text=re.sub(r'^archs:.*$','archs: [ armv7, armv7s, arm64 ]',stub.read_text(),flags=re.M)
        if str(stub.relative_to(sdk))=='usr/lib/libSystem.tbd':text=text.replace('symbols:            [ ','symbols:            [ _memcmp, _memset, _strcmp, _memcpy, _strncmp, ',1)
        out.write_text(text)
    source=adapt(build)
    js=build/'untether.js';js.write_bytes(b''.join((HERE/'upstream/untether/src'/(n+'.js')).read_bytes() for n in ('common','util','memory','system','dyld','exploit','patches','main')))
    clang=subprocess.check_output(['xcrun','--find','clang'],text=True).strip();ld=Path(clang).parent/'ld-classic'
    objects=[]
    for path in sorted((source/'src').glob('*.c'))+[HERE/'pathmap.c',HERE/'cache_rebase.c',HERE/'finalize.c']:
        obj=build/(path.stem+'.o');extra=[]
        if path.parent==source/'src':extra=['-DLIK_MAP_CALLS','-Dmain=procyon_original_main']
        run(clang,'-target','armv7-apple-ios10.0','-isysroot',sdk,'-Os','-Wall','-Wno-pointer-to-int-cast','-I',source/'include','-I',HERE,*extra,'-c',path,'-o',obj);objects.append(obj)
    final=build/'lik-restore-finalize'
    run(ld,'-arch','armv7','-iphoneos_version_min','10.0','-syslibroot',link,'-no_uuid','-lSystem','-framework','CoreFoundation',*objects,
        '-sectcreate','__DATA','__stage3',js,'-sectcreate','__DATA','__disabled',HERE/'upstream/resources/disabled.plist','-o',final)
    run(clang,'-target','armv7-apple-ios10.0','-isysroot',sdk,'-Os','-Wall','-Wextra','-Werror','-c',HERE/'nvram.c','-o',build/'nvram.o')
    run(ld,'-arch','armv7','-iphoneos_version_min','10.0','-syslibroot',link,'-no_uuid','-lSystem',build/'nvram.o','-o',build/'nvram')
    assets=HERE.parent/'assets';meta={'procyon_commit':(HERE/'upstream-commit').read_text().strip(),'source_sha256':{},'files_sha256':{},'hardware_tested':False}
    for path in sorted(HERE.rglob('*')):
        if path.is_file() and '__pycache__' not in str(path):meta['source_sha256'][str(path.relative_to(HERE))]=hashlib.sha256(path.read_bytes()).hexdigest()
    for name in ('lik-restore-finalize','nvram'):
        binary=build/name
        run('/usr/bin/codesign','--force','--sign','-','--timestamp=none','--digest-algorithm=sha1,sha256',binary)
        run('/usr/bin/codesign','--verify','--strict',binary)
        dest=assets/('allinone-'+name);shutil.copy2(binary,dest)
        meta['files_sha256'][dest.name]=hashlib.sha256(dest.read_bytes()).hexdigest()
    (assets/'allinone-build.json').write_text(json.dumps(meta,indent=2,sort_keys=True)+'\n')
    manifest=assets/'manifest.json';m=json.loads(manifest.read_text())
    for name in [*meta['files_sha256'],'allinone-build.json']:m['sha256'][name]=hashlib.sha256((assets/name).read_bytes()).hexdigest()
    m['allinone']={'build':'ios10-dev.14-allinone','source':'../allinone','hardware_tested':False};manifest.write_text(json.dumps(m,indent=2)+'\n')
    print('Built restore-only finalizer and nvram wrapper. Hardware validation pending.')
if __name__=='__main__':main()
