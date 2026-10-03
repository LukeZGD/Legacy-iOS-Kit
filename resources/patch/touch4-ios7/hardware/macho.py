# SPDX-License-Identifier: GPL-3.0-or-later
import struct
from pathlib import Path

def sections(blob):
    offset = 28
    for _ in range(struct.unpack_from('<I', blob, 16)[0]):
        command, size = struct.unpack_from('<II', blob, offset)
        if command == 1:
            count = struct.unpack_from('<I', blob, offset + 48)[0]
            for i in range(count):
                v = struct.unpack_from('<16s16s9I', blob, offset + 56 + i * 68)
                yield dict(name=v[0].rstrip(b'\0').decode(), segment=v[1].rstrip(b'\0').decode(),
                           address=v[2], size=v[3], offset=v[4])
        offset += size


class MachO:
 def __init__(self,path):
  self.b=Path(path).read_bytes(); self.secs=list(sections(self.b)); self.commands=[]; off=28
  for i in range(struct.unpack_from('<I',self.b,16)[0]):
   c,n=struct.unpack_from('<II',self.b,off); self.commands.append((c,off,n)); off+=n
  sy=next((o for c,o,n in self.commands if c==2),None)
  self.symbols=[]
  if sy:
   _,_,so,ns,st,sz=struct.unpack_from('<6I',self.b,sy)
   for i in range(ns):
    si,t,s,d,a=struct.unpack_from('<IBBHI',self.b,so+i*12); end=self.b.find(b'\0',st+si)
    self.symbols.append(dict(name=self.b[st+si:end].decode(),type=t,section=s,desc=d,address=a))
  self.relocations={}
  dy=next((o for c,o,n in self.commands if c==11),None)
  if dy:
   v=struct.unpack_from('<20I',self.b,dy)
   for ro,nr in [(v[16],v[17]),(v[18],v[19])]:
    for i in range(nr):
     a,info=struct.unpack_from('<II',self.b,ro+i*8)
     self.relocations[a]=dict(symbol=info&0xffffff,pcrel=(info>>24)&1,length=(info>>25)&3,external=(info>>27)&1,kind=info>>28)
  self.names={s['name']:s for s in self.symbols if s['type']&0xe==0xe and not s['type']&0xe0}
  self.byaddr={}
  for s in self.names.values(): self.byaddr.setdefault(s['address'],[]).append(s['name'])
 def offset(self,a):
  s=next(s for s in self.secs if s['address']<=a<s['address']+s['size']); return s['offset']+a-s['address']
 def word(self,a): return struct.unpack_from('<I',self.b,self.offset(a))[0]
 def pointer_names(self,a):
  r=self.relocations.get(a)
  if r and r['external']: return [self.symbols[r['symbol']]['name']]
  v=self.word(a); return self.byaddr.get(v&~1,[]) or self.byaddr.get(v,[])
