from pathlib import Path
R=Path(__file__).resolve().parent

def svg(name,body):
 return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256" role="img" aria-label="{name}"><title>Naturebook — {name}</title>{body}</svg>'
N='M36 222V103Q36 100 39 100H71Q74 100 74 103V116C85 102 101 94 120 94C158 94 180 120 180 158V222C156 220 143 210 143 191V158C143 138 134 127 117 127C95 127 75 139 75 161V191C75 210 61 220 36 222Z'
# A reduced monarch: elongated forewings, rounded hindwings, strong veins, and pale border spots.
OUTER='M128 74C120 74 116 82 116 94V104C94 69 59 35 27 22C19 53 25 87 39 112C47 126 58 136 72 143C49 145 36 162 41 183C47 210 77 229 111 208C118 216 122 228 128 232C134 228 138 216 145 208C179 229 209 210 215 183C220 162 207 145 184 143C198 136 209 126 217 112C231 87 237 53 229 22C197 35 162 69 140 104V94C140 82 136 74 128 74Z'
LEFT=[
'M48 51C70 64 92 85 107 113C82 106 60 84 48 51Z',
'M43 88C59 108 78 120 104 126C86 137 65 133 53 118C47 111 44 100 43 88Z',
'M103 146C87 142 70 147 60 157C58 168 63 180 72 186Z',
'M111 154L84 194C92 202 103 204 113 197Z']
def mirrorpath(p):
 # Keep the actual mirrored geometry in the same path so the counters remain holes.
 import re
 tokens=re.findall(r'[A-Za-z]|-?\d+(?:\.\d+)?',p);out=[];cmd='';i=0
 counts={'M':2,'L':2,'C':6,'Q':4,'Z':0}
 while i<len(tokens):
  if tokens[i].isalpha():
   cmd=tokens[i];out.append(cmd);i+=1
   if cmd=='Z':continue
  ct=counts[cmd];vs=[float(x) for x in tokens[i:i+ct]];i+=ct
  for j in range(0,ct,2):vs[j]=256-vs[j]
  out.extend(f'{v:g}' for v in vs)
 return ' '.join(out)
CELLS=LEFT+[mirrorpath(p) for p in LEFT]
def circle(x,y,r):return f'M{x-r} {y}A{r} {r} 0 1 0 {x+r} {y}A{r} {r} 0 1 0 {x-r} {y}Z'
SPOTS=' '.join(circle(x,y,5) for x,y in [(34,43),(34,65),(48,142),(222,43),(222,65),(208,142)])
ANTENNA='M122 82C120 66 115 56 107 51L110 46C122 54 127 65 128 79Z M134 82C136 66 141 56 149 51L146 46C134 54 129 65 128 79Z'

def butterfly(detail=True,color=False):
 if color:
  return f'<path fill="#000000" fill-rule="evenodd" d="{OUTER} {SPOTS}"/><path fill="#C96B26" d="{" ".join(CELLS)}"/><path fill="#000000" d="{ANTENNA}"/>'
 holes=' '.join(CELLS)+' '+SPOTS if detail else ' '.join([LEFT[0],LEFT[2],mirrorpath(LEFT[0]),mirrorpath(LEFT[2])])
 return f'<path fill="#000000" fill-rule="evenodd" d="{OUTER} {holes}"/>'+ (f'<path fill="#000000" d="{ANTENNA}"/>' if detail else '')

def composition(scale=.47,tx=120,ty=12,angle=18,detail=True,color=False):
 return f'<path fill="#000000" d="{N}"/><g transform="translate({tx} {ty}) scale({scale}) rotate({angle} 128 128)">{butterfly(detail,color)}</g>'
A=composition()
B=composition(.43,114,21,12)
C=composition(.5,113,8,18)
for key,body in [('a',A),('b',B),('c',C)]: (R/'iterations'/f'{key}-v1.svg').write_text(svg('Lowercase n with monarch / '+key,body))

def sheet(name,items):
 out=['<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="860" viewBox="0 0 1440 860"><rect width="1440" height="860" fill="white"/>',f'<text x="40" y="55" font-family="Helvetica" font-size="28">Naturebook / lowercase n + monarch / {name}</text>']
 for i,(label,body) in enumerate(items):
  x=40+470*i
  out += [f'<text x="{x}" y="112" font-family="Helvetica" font-size="22">{label}</text>',f'<g transform="translate({x+30} 145) scale(1.4)">{body}</g>',f'<rect x="{x}" y="575" width="160" height="160" rx="36" fill="black"/>',f'<g transform="translate({x} 575) scale(.625)">{body.replace("#000000","#ffffff")}</g>']
  for j,s in enumerate([64,32,16]):
   xx=x+205+j*80
   out += [f'<g transform="translate({xx} 625) scale({s/256})">{body}</g>',f'<text x="{xx}" y="745" font-family="Helvetica" font-size="13">{s}px</text>']
 out.append('</svg>');(R/'tests'/f'{name}.svg').write_text('\n'.join(out))
sheet('v1',[('A / open wings',A),('B / quieter butterfly',B),('C / larger butterfly',C)])

# Pass two: remove two spots outside the border; keep wing holes clear of the n.
SPOTS=' '.join(circle(x,y,5) for x,y in [(34,43),(34,65),(222,43),(222,65)])
N2=f'<g transform="translate(0 6)"><path fill="#000000" d="{N}"/></g>'
def revised(detail=True,color=False,dx=0,dy=0):
 return N2+f'<g transform="translate({126+dx} {17+dy}) scale(.44) rotate(18 128 128)">{butterfly(detail,color)}</g>'
V2=revised()
V2COLOR=revised(color=True)
V2SMALL=revised(detail=False)
for key,body in [('mono',V2),('color',V2COLOR),('small',V2SMALL)]:
 (R/'iterations'/f'{key}-v2.svg').write_text(svg('Lowercase n and monarch / '+key,body))
sheet('v2',[('Monochrome',V2),('Monarch orange / exploratory',V2COLOR),('Small-size pattern',V2SMALL)])

# Pass three: round the pointed n feet very slightly and bake all transforms.
import math,re
N3=N.replace('M36 222','M38 221.8Q36 222 36 220').replace('V222C156 220','V220Q180 222 178 221.8C156 220')
# Keep a clear wing/letter gap, rather than a hairline contact.
BX,BY,BS,BA=127,15,.44,18

def bake(d,fn,scale=1,angle=0):
 t=re.findall(r'[A-Za-z]|-?\d+(?:\.\d+)?',d);out=[];i=0;cmd='';last=(0,0);start=(0,0)
 sizes={'M':2,'L':2,'C':6,'Q':4,'H':1,'V':1,'A':7,'Z':0}
 def f(v):return ('%.2f'%v).rstrip('0').rstrip('.')
 while i<len(t):
  if t[i].isalpha():
   cmd=t[i];i+=1
   if cmd=='Z':out.append('Z');last=start;continue
  k=sizes[cmd];v=[float(x) for x in t[i:i+k]];i+=k
  if cmd in ['H','V']:
   last=(v[0],last[1]) if cmd=='H' else (last[0],v[0]);out.extend(['L',*[f(a) for a in fn(*last)]]);continue
  if cmd=='A':
   last=(v[5],v[6]);xy=fn(*last)
   out.extend(['A',f(v[0]*scale),f(v[1]*scale),f(v[2]+angle),f(v[3]),f(v[4]),f(xy[0]),f(xy[1])]);continue
  res=[]
  for j in range(0,k,2):res.extend(fn(v[j],v[j+1]))
  last=(v[-2],v[-1]);out.extend([cmd,*[f(a) for a in res]])
  if cmd=='M':start=last
 return ' '.join(out)

def bfpoint(x,y):
 a=math.radians(BA);x-=128;y-=128
 return BX+BS*(128+x*math.cos(a)-y*math.sin(a)),BY+BS*(128+x*math.sin(a)+y*math.cos(a))
def path(d,fill='#000000',fn=bfpoint,scale=BS,angle=BA):
 return f'<path fill="{fill}" fill-rule="evenodd" d="{bake(d,fn,scale,angle)}"/>'
LETTER=path(N3,fn=lambda x,y:(x,y+6),scale=1,angle=0)
MONO=LETTER+path(OUTER+' '+' '.join(CELLS)+' '+SPOTS)+path(ANTENNA)
COLOR=LETTER+path(OUTER+' '+SPOTS)+path(' '.join(CELLS),'#C96B26')+path(ANTENNA)
SMALL=LETTER+path(OUTER+' '+' '.join([LEFT[0],LEFT[2],mirrorpath(LEFT[0]),mirrorpath(LEFT[2])]))
for key,body in [('mono',MONO),('color-study',COLOR),('small',SMALL)]:
 (R/'iterations'/f'{key}-v3.svg').write_text(svg('n + monarch / '+key,body))
 (R/'concepts'/f'n-monarch-{key}.svg').write_text(svg('Lowercase n with monarch / '+key,body))
sheet('v3',[('Monochrome',MONO),('Monarch orange / study only',COLOR),('Small-size pattern',SMALL)])

# Final optical placement: more space above/right, and a deliberate 15-degree butterfly pose.
BX,BY,BS,BA=119,19,.44,15
LETTER=path(N3,fn=lambda x,y:(x-8,y+10),scale=1,angle=0)
MONO=LETTER+path(OUTER+' '+' '.join(CELLS)+' '+SPOTS)+path(ANTENNA)
COLOR=LETTER+path(OUTER+' '+SPOTS)+path(' '.join(CELLS),'#C96B26')+path(ANTENNA)
SMALL=LETTER+path(OUTER+' '+' '.join([LEFT[0],LEFT[2],mirrorpath(LEFT[0]),mirrorpath(LEFT[2])]))
for key,body in [('mono',MONO),('color-study',COLOR),('small',SMALL)]:
 (R/'iterations'/f'{key}-v4.svg').write_text(svg('n + monarch / '+key,body))
 (R/'concepts'/f'n-monarch-{key}.svg').write_text(svg('Lowercase n with monarch / '+key,body))
sheet('v4',[('Monochrome',MONO),('Monarch orange / study only',COLOR),('Small-size pattern',SMALL)])

# Align the mirrored inner hindwing cell boundaries before the common 15-degree rotation.
LEFT[3]='M111 154L84 194C92 202 103 204 111 197Z'
CELLS=LEFT+[mirrorpath(p) for p in LEFT]
MONO=LETTER+path(OUTER+' '+' '.join(CELLS)+' '+SPOTS)+path(ANTENNA)
COLOR=LETTER+path(OUTER+' '+SPOTS)+path(' '.join(CELLS),'#C96B26')+path(ANTENNA)
for key,body in [('mono',MONO),('color-study',COLOR),('small',SMALL)]:
 (R/'iterations'/f'{key}-v5.svg').write_text(svg('n + monarch / '+key,body))
 (R/'concepts'/f'n-monarch-{key}.svg').write_text(svg('Lowercase n with monarch / '+key,body))
