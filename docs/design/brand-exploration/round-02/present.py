from pathlib import Path
import base64
from html import escape
import runpy
R=Path(__file__).resolve().parent
items=runpy.run_path(str(R/'build.py'))['FINAL']

def text(x,y,s,size=18,color='#000',weight='400',family='Helvetica,Arial,sans-serif'):
 return f'<text x="{x}" y="{y}" font-family="{family}" font-size="{size}" font-weight="{weight}" fill="{color}">{escape(s)}</text>'
def lineblock(x,y,rows,size=18,color='#333'):
 return ''.join(text(x,y+j*27,s,size,color) for j,s in enumerate(rows))
def raster(l,name,size):
 stem=f'{l}-{name.lower().replace(" ","-")}'
 if l=='a' and size<64:stem+='-small'
 p=R/'renders'/str(size)/(stem+'.png')
 return 'data:image/png;base64,'+base64.b64encode(p.read_bytes()).decode()

out=['<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1110" viewBox="0 0 1600 1110"><rect width="1600" height="1110" fill="white"/>']
out += [text(64,51,'NATUREBOOK / ROUND 02',14,'#555','600'),text(1287,51,'07 NOVEMBER 2026',14,'#555'),text(64,116,'Nature in the silhouette.',49,family='Georgia,serif'),text(64,160,'An unfurling fern, an insect in flight, and an inquisitive bird. Three recognizably living forms.',20,'#444'),'<path d="M64 190H1536" stroke="#222"/>']
notes=[
(['The N grows into a fern frond:', 'a coiled tip and two broad leaflets.'], ['Strongest link between name and nature.', 'Risk: can feel ornamental or plant-specific.']),
(['Sweeping forewings and carved openings', 'create a compact insect silhouette.'], ['Immediate nature cue; balanced and bold.', 'Risk: familiar butterfly territory.']),
(['A cocked tail and curved wing opening', 'give a small bird an attentive character.'], ['Warmest, most characterful alternative.', 'Risk: could suggest a bird-only app.'])]
for i,((l,n,b),(idea,risk)) in enumerate(zip(items,notes)):
 x=64+i*504
 if i:out.append(f'<path d="M{x-24} 220V989" stroke="#ddd"/>')
 out += [text(x,240,f'{l.upper()} / {n}',29,family='Georgia,serif')]
 out.append(f'<g transform="translate({x+55} 279) scale(1.3)">{b}</g>')
 out += [f'<rect x="{x}" y="638" width="112" height="112" rx="25" fill="black"/>',f'<g transform="translate({x} 638) scale(.4375)">{b.replace("#000000","#ffffff")}</g>',text(x,777,'REVERSED',11,'#555')]
 for j,s in enumerate([64,32,16]):
  xx=x+174+j*98
  out += [f'<image x="{xx}" y="{675+(64-s)/2}" width="{s}" height="{s}" href="{raster(l,n,s)}"/>',text(xx,777,str(s)+' px'+('*' if l=='a' and s<64 else ''),12,'#555')]
 out += [lineblock(x,830,idea),lineblock(x,921,risk,17)]
 if l=='a':out.append(text(x,977,'* Simplified rolled tip at 16–32 px.',12,'#666'))
out += ['<path d="M64 1007H1536" stroke="#222"/>',text(64,1046,'A is the strongest direction to develop; C offers the most personality.',22,family='Georgia,serif'),text(64,1080,'Concept studies only. Black and white. No production assets changed.',15,'#555'),'</svg>']
(R/'comparison-board.svg').write_text('\n'.join(out))

proof=['<!doctype html><meta charset="utf-8"><style>*{box-sizing:border-box}body{font-family:Helvetica,Arial;margin:0;padding:35px;width:1500px;background:white}h1{font-size:28px}.row{display:flex;align-items:center;gap:40px;padding:28px 0;border-top:1px solid #ccc}.name{width:160px}.item{text-align:center;width:160px;font-size:13px}.sample{height:140px;display:flex;align-items:center;justify-content:center}.sample svg{width:120px;height:120px}.dark{background:black;border-radius:26px}.pixel{image-rendering:pixelated;width:128px;height:128px}.ref{display:flex;gap:60px;align-items:center}.ref svg{width:90px;height:90px}.ref figure{margin:15px 0;text-align:center;font-size:13px}</style><h1>Round 02 / visual checks</h1><p>Actual 16 px rasters enlarged 8×; the fern uses its small-size cut.</p>']
for l,n,b in items:
 def sv(content):return f'<svg viewBox="0 0 256 256">{content}</svg>'
 cases=[('Normal',sv(b)),('Reversed',f'<div class="dark">{sv(b.replace("#000000","#ffffff"))}</div>'),('Mirror',sv(f'<g transform="translate(256 0) scale(-1 1)">{b}</g>')),('180 degrees',sv(f'<g transform="rotate(180 128 128)">{b}</g>')),('Squint',f'<div style="filter:blur(3px)">{sv(b)}</div>'),('16 px × 8',f'<img class="pixel" src="{raster(l,n,16)}">')]
 proof.append(f'<div class="row"><div class="name"><b>{n}</b></div>')
 for label,content in cases:proof.append(f'<div class="item"><div class="sample">{content}</div><p>{label}</p></div>')
 proof.append('</div>')
proof.append('<h2>Construction references / trademarks of their respective owners</h2><div class="ref">')
lib=Path('/Users/emreerdener/.codex/skills/logo-design/assets/library/svg')
for name in ['twitter','gnome-icon','khan_academy-icon','dreamhost']:
 proof.append(f'<figure>{(lib/(name+".svg")).read_text()}<figcaption>{name}</figcaption></figure>')
proof.append('</div><p>Visual screening only. No trademark clearance or independent recognition test is claimed.</p>')
(R/'tests/visual-proof.html').write_text('\n'.join(proof))
