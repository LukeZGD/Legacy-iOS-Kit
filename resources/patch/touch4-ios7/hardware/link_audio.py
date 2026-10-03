# SPDX-License-Identifier: GPL-3.0-or-later
"""Relink the hash-pinned CS42L59 donor into the 11D257 N92 kernel."""
from pathlib import Path
from macho import MachO
from inspect_kernel import segments,metadata
import struct,json,plistlib,xml.etree.ElementTree as ET,hashlib,re,argparse

def check(path, expected):
    actual=hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected:
        raise ValueError(f"Unsupported input {path.name}: SHA256 {actual}, expected {expected}")

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--kernel',type=Path,required=True)
parser.add_argument('--kext',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
args=parser.parse_args()
check(args.kernel,'70cead59899008cc7cbd75020760b9a0da39498dc7d694cc61cc9ea4ad831489')
check(args.kext/'AppleCS42L59Audio','1970eb6c0754bd313e1b957e60d4149c9f48a60ede7363adc84419bea281cf88')
check(args.kext/'Info.plist','cd15cf00a8d3face0857dbb2b2ba394f276bf3720e9b29c17afe18eb008cf7c0')
OUT=args.output.resolve(); OUT.mkdir(parents=True,exist_ok=True)
KERNEL_NAME='kernel.cs59.macho'
n=MachO(args.kext/'AppleCS42L59Audio');k=MachO(args.kernel)
meta=metadata(k.b); old=next(d for d in meta['_PrelinkInfoDictionary'] if d['CFBundleIdentifier']=='com.apple.driver.AppleCS42L61Audio')
load=old['_PrelinkExecutableLoadAddr'];pretext=next(s for s in segments(k.b) if s['name']=='__PRELINK_TEXT');info=next(s for s in segments(k.b) if s['name']=='__PRELINK_INFO')
start=pretext['offset']+load-pretext['address'];assert start+old['_PrelinkExecutableSize']==info['offset']
symbols=json.loads((Path(__file__).with_name('symbol-map.json')).read_text())
b=bytearray(n.b[:0x4000]); relocs=dict(n.relocations); audit=[]
for a,r in relocs.items():
 assert (r['kind'],r['length'],r['pcrel'])==(0,2,0)
 oldval=struct.unpack_from('<I',b,a)[0]
 if r['external']:
  name=n.symbols[r['symbol']]['name'];assert name in symbols;assert oldval==0;value=symbols[name]
 else:
  name='local';assert 0<=oldval<0x4000;value=load+oldval
 struct.pack_into('<I',b,a,value); audit.append(dict(offset=a,source=name,before=oldval,after=value))
# 7.1 adds one IOHIDEventService virtual slot inherited by the Mikey class.
# The runtime panic confirmed that all methods after this slot shifted by four bytes.
# There is sufficient unused padding
# before the following MetaClass vtable, so every original symbol address stays fixed.
vt=n.names['__ZTV17AppleCS42L59Mikey']['address'];insert=vt+0x3c0;end=vt+0x4b4
assert b[end:end+12]==bytes(12)
b[insert+4:end+4]=b[insert:end]
struct.pack_into('<I',b,insert,0x8091443d)
# A compiled call through the superclass vtable also uses the old table offset.
# Audio-object virtual register calls in the remaining Mikey methods are unchanged.
callsite=n.offset(0x29ac);assert n.b[callsite:callsite+4]==bytes.fromhex('d0f8f013')
b[callsite:callsite+4]=bytes.fromhex('d0f8f413')
newrel=[]
for a in relocs: newrel.append(a+4 if insert<=a<end else a)
newrel.append(insert);newrel.sort();assert len(set(newrel))==len(newrel)
# Replace symbol table and external relocations with resolved KASLR local fixups.
linkedit=bytearray()
for a in newrel:linkedit+=struct.pack('<II',a,1|(2<<25))
linksize=(len(linkedit)+4095)&~4095;size=0x4000+linksize;b+=linkedit+bytes(linksize-len(linkedit))
commands=[]
for c,o,z in n.commands:
 if c==2:continue
 raw=bytearray(n.b[o:o+z])
 if c==1:
  vm,vmz,fo,fs=struct.unpack_from('<4I',raw,24)
  if raw[8:24].rstrip(b'\0')==b'__LINKEDIT':vmz=fs=linksize
  struct.pack_into('<4I',raw,24,load+vm,vmz,fo,fs)
  for i in range(struct.unpack_from('<I',raw,48)[0]):
   so=56+i*68;addr=struct.unpack_from('<I',raw,so+32)[0];struct.pack_into('<I',raw,so+32,addr+load)
 elif c==11:
  raw=bytearray(struct.pack('<20I',11,80,*([0]*16),0x4000,len(newrel)))
 commands.append(raw)
struct.pack_into('<I',b,8,9) # ARM_V7; instruction audit is required separately.
struct.pack_into('<II',b,16,len(commands),sum(map(len,commands)))
b[28:1020]=bytes(992);pos=28
for raw in commands:b[pos:pos+len(raw)]=raw;pos+=len(raw)
# Bootstrap adjusts kmod_info.address separately from relocation fixups.
kmod=n.names['_kmod_info']['address'];assert kmod+148 not in newrel
struct.pack_into('<III',b,kmod+148,load,size,0)
(OUT/'AppleCS42L59Audio.prelinked').write_bytes(b)
new=plistlib.loads((args.kext/'Info.plist').read_bytes())
for key in ['_PrelinkExecutableLoadAddr','_PrelinkExecutableSourceAddr']:new[key]=load
new.update(_PrelinkExecutableSize=size,_PrelinkKmodInfo=load+kmod,_PrelinkExecutableRelativePath='AppleCS42L59Audio',_PrelinkBundlePath='/System/Library/Extensions/AppleEmbeddedAudio.kext/PlugIns/AppleCS42L59Audio.kext')
meta['_PrelinkInfoDictionary'][meta['_PrelinkInfoDictionary'].index(old)]=new
# Preserve the original XML node types and ID/IDREF graph. The read-only metadata
# helper flattens OSData to strings and must never serialize unaffected kexts.
root=ET.fromstring(k.b[info['offset']:info['offset']+info['size']].rstrip(b'\0'))
ids={e.attrib['ID']:e for e in root.iter() if 'ID' in e.attrib}
def deref(e):
 while 'IDREF' in e.attrib:e=ids[e.attrib['IDREF']]
 return e
def pair_value(d,key):
 children=list(d)
 for i in range(0,len(children),2):
  if deref(children[i]).text==key:return deref(children[i+1])
array=pair_value(root,'_PrelinkInfoDictionary');entry=next(e for e in array if pair_value(e,'CFBundleIdentifier').text=='com.apple.driver.AppleCS42L61Audio')
replacement=ET.fromstring(plistlib.dumps(new,sort_keys=False))[0]
old_ids={e.attrib['ID'] for e in entry.iter() if 'ID' in e.attrib}
external_refs={e.attrib['IDREF'] for e in root.iter() if 'IDREF' in e.attrib and e not in set(entry.iter())}
# Keep the old dict ID if referenced; descendants must not be shared externally.
if 'ID' in entry.attrib:replacement.attrib['ID']=entry.attrib['ID'];old_ids.remove(entry.attrib['ID'])
assert not old_ids&external_refs
array[list(array).index(entry)]=replacement
valid_ids={e.attrib['ID'] for e in root.iter() if 'ID' in e.attrib}
assert all(e.attrib['IDREF'] in valid_ids for e in root.iter() if 'IDREF' in e.attrib)
xml=re.sub(rb'(<[A-Za-z][^<>]*?)\s+/>',rb'\1/>',ET.tostring(root,encoding='utf-8'))+b'\0'
growth=size-old['_PrelinkExecutableSize'];newinfo=info['offset']+growth;newinfova=info['address']+growth;ivmsize=(len(xml)+4095)&~4095
result=bytearray(k.b[:start])+b+xml+bytes(ivmsize-len(xml));assert len(result)==newinfo+ivmsize
for c,o,z in k.commands:
 if c!=1:continue
 segname=k.b[o+8:o+24].rstrip(b'\0')
 if segname==b'__PRELINK_TEXT':
  for field in [28,36]:struct.pack_into('<I',result,o+field,struct.unpack_from('<I',result,o+field)[0]+growth)
  for i in range(struct.unpack_from('<I',result,o+48)[0]):
   so=o+56+i*68;struct.pack_into('<I',result,so+36,struct.unpack_from('<I',result,so+36)[0]+growth)
 elif segname==b'__PRELINK_INFO':
  struct.pack_into('<4I',result,o+24,newinfova,ivmsize,newinfo,len(xml))
  assert struct.unpack_from('<I',result,o+48)[0]==1
  struct.pack_into('<II',result,o+56+32,newinfova,len(xml))
(OUT/KERNEL_NAME).write_bytes(result)
assert metadata(result)==meta
assert len(list(ET.fromstring(xml.rstrip(b'\0')).iter('data')))==14
# Re-read the final image and validate all relocation targets lie in mapped memory.
final=MachO(OUT/'AppleCS42L59Audio.prelinked');ranges=[(s['address'],s['address']+s['vmsize']) for s in segments(result)]
for a,r in final.relocations.items():
 v=struct.unpack_from('<I',final.b,a)[0];assert any(lo<=v<hi for lo,hi in ranges),(hex(a),hex(v))
report=dict(status='CS59 linker output; v6 hardware verified with manual RAM activation; automatic loading unverified',load_address=hex(load),driver_bytes=size,relocations=len(newrel),inserted_virtual_slot=hex(insert),inherited_slot_offset='0x3c0 in vtable, 0x3b8 in object',superclass_call_patch='native text 0x29ac: vtable offset 0x3f0 -> 0x3f4',kernel_growth=growth,metadata_bytes=len(xml),sha256=hashlib.sha256(result).hexdigest(),resolved_imports=sorted({r['source'] for r in audit if r['source']!='local'}))
(OUT/'build-audit.json').write_text(json.dumps(report,indent=2));(OUT/'relocation-audit.json').write_text(json.dumps(audit,indent=2))
print(json.dumps({k:v for k,v in report.items() if k!='resolved_imports'},indent=2))

check(OUT/KERNEL_NAME,'0742b236a5e9504a3a3d1df8f4773c495f3b8a01ef7576127d590f48ec3ea847')
