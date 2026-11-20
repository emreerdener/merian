from pathlib import Path
from html import escape
R=Path(__file__).resolve().parent

def svg(name,body):
 return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256" role="img" aria-label="{name}"><title>Naturebook — {name}</title>{body}</svg>'

# Fern N: a rooted stem, a diagonal, a coiled fiddlehead and two broad pinnae.
A1='<path fill="#000000" d="M36 216V82C36 58 50 44 69 44C83 44 94 54 103 68L151 143V80C151 48 167 30 190 30C216 30 232 48 232 70C232 94 216 109 194 109C176 109 165 98 165 83C165 69 174 59 186 59C197 59 204 65 204 75C204 83 199 89 191 89C186 89 182 87 179 84C180 93 187 98 196 98C210 98 219 87 219 72C219 57 209 47 195 47C176 47 172 64 172 84V139C186 124 204 115 224 116C220 139 199 154 172 156V180C187 166 205 159 224 160C220 187 202 202 177 204C174 215 166 222 155 222C144 222 136 215 128 203L72 116V175C72 196 59 210 36 216Z"/>'
# Field moth: rounded hindwings, sweeping forewings, and paired bold wing windows.
B1='<path fill="#000000" fill-rule="evenodd" d="M128 70C120 70 116 78 116 88V99C93 73 62 48 28 38C21 47 25 67 30 90C37 113 50 128 72 140C47 141 39 163 49 184C61 211 90 217 116 199L121 217Q128 228 135 217L140 199C166 217 195 211 207 184C217 163 209 141 184 140C206 128 219 113 226 90C231 67 235 47 228 38C194 48 163 73 140 99V88C140 78 136 70 128 70Z M54 71C76 78 98 96 109 115C84 112 64 95 54 71Z M202 71C180 78 158 96 147 115C172 112 192 95 202 71Z"/>'
# Inquisitive wren: cocked tail, a bowed head, and a broad carved wing.
C1='<path fill="#000000" fill-rule="evenodd" d="M52 204C56 185 55 163 50 147C30 120 22 80 30 45C53 71 72 98 94 114C110 100 129 93 147 94C150 68 180 62 200 78C214 90 217 108 209 124L230 146L201 141C191 174 164 198 129 205C100 211 76 210 52 204Z M86 147C106 124 140 119 167 130C140 139 122 159 112 184C96 177 87 164 86 147Z M188 98A8 8 0 1 0 188 114A8 8 0 1 0 188 98Z"/>'
V1=[('a','Fiddlehead N',A1),('b','Field moth',B1),('c','Curious wren',C1)]

def sheet(version,items):
 out=['<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="900" viewBox="0 0 1440 900"><rect width="1440" height="900" fill="white"/>',f'<text x="40" y="55" font-family="Helvetica" font-size="28">Naturebook · round 02 / {version}</text>']
 for i,(letter,name,body) in enumerate(items):
  x=40+i*470
  out += [f'<text x="{x}" y="115" font-family="Helvetica" font-size="23">{letter.upper()} / {escape(name)}</text>',f'<g transform="translate({x+35} 160) scale(1.4)">{body}</g>',f'<rect x="{x}" y="590" width="160" height="160" rx="36" fill="black"/>',f'<g transform="translate({x} 590) scale(.625)">{body.replace("#000000","#ffffff")}</g>']
  for j,s in enumerate([64,32,16]):
   xx=x+205+j*80
   out += [f'<g transform="translate({xx} 640) scale({s/256})">{body}</g>',f'<text x="{xx}" y="750" font-family="Helvetica" font-size="13">{s}px</text>']
 out.append('</svg>')
 (R/'tests'/f'{version}.svg').write_text('\n'.join(out))
for l,n,b in V1: (R/'iterations'/f'{l}-v1.svg').write_text(svg(n,b))
sheet('v1',V1)

# Pass two: broader fern curl; calmer hindwings; shorter tail and smaller eye.
A2='<path fill="#000000" d="M32 216V84C32 59 46 44 65 44C80 44 91 56 102 74C120 103 133 128 148 141V83C148 48 165 27 191 27C216 27 232 45 232 68C232 93 216 109 194 109C175 109 163 97 163 82C163 68 172 58 184 58C196 58 203 66 203 75C203 83 198 88 192 89C207 90 215 81 215 69C215 55 205 46 192 46C174 46 169 63 169 84V138C183 123 201 114 222 114C219 138 198 153 169 156V179C184 165 202 159 222 159C219 184 201 201 174 204C171 216 163 222 152 222C140 222 132 214 123 199C105 170 91 139 69 117V174C69 196 55 210 32 216Z"/>'
B2='<path fill="#000000" fill-rule="evenodd" d="M128 68C121 68 116 76 116 86V98C91 71 59 48 28 40C23 56 28 79 35 98C44 119 57 130 75 140C56 143 44 157 48 174C53 198 79 211 112 195C116 205 121 216 128 220C135 216 140 205 144 195C177 211 203 198 208 174C212 157 200 143 181 140C199 130 212 119 221 98C228 79 233 56 228 40C197 48 165 71 140 98V86C140 76 135 68 128 68Z M54 72C75 79 95 94 108 115C84 113 64 98 54 72Z M202 72C181 79 161 94 148 115C172 113 192 98 202 72Z"/>'
C2='<path fill="#000000" fill-rule="evenodd" d="M53 204C57 185 56 163 51 147C35 125 28 94 32 63C53 84 74 104 94 116C110 102 129 95 147 96C150 70 180 65 200 81C214 92 216 109 208 125L228 145L201 141C191 174 164 198 129 205C100 211 77 210 53 204Z M86 147C107 124 140 120 167 131C139 141 121 160 112 183C97 177 88 164 86 147Z M187 99A7 7 0 1 0 187 113A7 7 0 1 0 187 99Z"/>'
V2=[('a','Fiddlehead N',A2),('b','Fieldwing',B2),('c','Curious wren',C2)]
for l,n,b in V2: (R/'iterations'/f'{l}-v2.svg').write_text(svg(n,b))
sheet('v2',V2)

# Pass three: controlled placement and softer wing shoulders. Store the small-size cut separately.
import re

def shift(body,dx,dy):
 def path(m):
  tokens=re.findall(r'[A-Za-z]|-?\d+(?:\.\d+)?',m.group(1))
  out=[];cmd='';i=0
  counts={'M':2,'L':2,'C':6,'Q':4,'V':1,'H':1,'A':7,'Z':0}
  while i<len(tokens):
   if tokens[i].isalpha():
    cmd=tokens[i];out.append(cmd);i+=1
    if cmd=='Z':continue
   count=counts[cmd];v=[float(t) for t in tokens[i:i+count]];i+=count
   if cmd=='A':v[5]+=dx;v[6]+=dy
   elif cmd=='V':v[0]+=dy
   elif cmd=='H':v[0]+=dx
   else:
    for j in range(count):v[j]+=dx if j%2==0 else dy
   out.extend(f'{a:g}' for a in v)
  return 'd="'+' '.join(out)+'"'
 return re.sub(r'd="([^"]+)"',path,body)
A3=shift(A2,-4,0)
B3=B2.replace('C91 71 59 48 28 40C23 56','C91 71 60 49 31 41Q28 40 27 43C24 58').replace('233 56 228 40C197 48','232 58 229 43Q228 40 225 41C196 49')
C3=shift(C2,0,-10)
FINAL=[('a','Fiddlehead N',A3),('b','Fieldwing',B3),('c','Curious wren',C3)]
# At 16/32 px the fiddlehead is a bold rolled tip with one open counter.
ASMALL='<path fill="#000000" fill-rule="evenodd" d="M28 216V84C28 59 42 44 61 44C76 44 87 56 98 74C116 103 129 128 144 141V83C144 48 161 27 187 27C212 27 228 45 228 68C228 93 212 109 190 109C180 109 171 105 165 99V138C179 123 197 114 218 114C215 138 194 153 165 156V179C180 165 198 159 218 159C215 184 197 201 170 204C167 216 159 222 148 222C136 222 128 214 119 199C101 170 87 139 65 117V174C65 196 51 210 28 216Z M187 47C175 47 169 57 169 68C169 80 177 89 190 89C201 89 208 80 208 68C208 56 199 47 187 47Z"/>'
for l,n,b in FINAL:
 (R/'iterations'/f'{l}-v3.svg').write_text(svg(n,b))
 (R/'concepts'/f'{l}-{n.lower().replace(" ","-")}.svg').write_text(svg(n,b))
(R/'concepts/a-fiddlehead-n-small.svg').write_text(svg('Fiddlehead N small-size study',ASMALL))
sheet('v3',FINAL)
sheet('small-cut',[('a','N / simplified rolled tip',ASMALL),('b','Fieldwing',B3),('c','Curious wren',C3)])
