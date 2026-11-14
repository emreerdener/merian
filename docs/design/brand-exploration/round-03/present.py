from pathlib import Path
import runpy,base64
from html import escape
R=Path(__file__).resolve().parent
d=runpy.run_path(str(R/'build.py'));mono=d['MONO'];color=d['COLOR'];small=d['SMALL']
def t(x,y,s,size=18,fill='#000',family='Helvetica,Arial,sans-serif'):
 return f'<text x="{x}" y="{y}" font-family="{family}" font-size="{size}" fill="{fill}">{escape(s)}</text>'
def im(size,x,y,w=None):
 src='data:image/png;base64,'+base64.b64encode((R/'renders'/f'n-monarch-{size}.png').read_bytes()).decode()
 return f'<image x="{x}" y="{y}" width="{w or size}" height="{w or size}" href="{src}"/>'
board=['<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="1000" viewBox="0 0 1440 1000"><rect width="1440" height="1000" fill="white"/>',t(60,53,'NATUREBOOK / LOWERCASE n + MONARCH',14,'#555'),t(60,121,'A small encounter.',49,family='Georgia,serif'),t(60,164,'A soft lowercase n with a monarch poised over its shoulder.',21,'#444'),'<path d="M60 197H1380" stroke="#ccc"/>',f'<g transform="translate(160 240) scale(2)">{mono}</g>','<path d="M820 240V865" stroke="#ddd"/>']
board += ['<rect x="900" y="280" width="180" height="180" rx="40" fill="#f7f5f0"/>',f'<g transform="translate(900 280) scale(.703125)">{color}</g>','<rect x="1160" y="280" width="180" height="180" rx="40" fill="black"/>',f'<g transform="translate(1160 280) scale(.703125)">{mono.replace("#000000","#ffffff")}</g>',t(900,498,'Monarch orange study',15,'#555'),t(1160,498,'One-colour reversal',15,'#555')]
for size,x in [(64,920),(32,1090),(16,1255)]:
 board += [im(size,x,595+(64-size)/2),t(x,705,str(size)+' px'+(' · simplified' if size<64 else ''),14,'#555')]
board += [t(900,778,'Broad wing cells and border spots',20,family='Georgia,serif'),t(900,807,'carry the monarch character at larger sizes.',17,'#555'),t(900,850,'At 16–32 px, the butterfly uses fewer openings.',16,'#555'),t(60,826,'Custom letterform / no font dependency',15,'#555'),'<path d="M60 902H1380" stroke="#ccc"/>',t(60,946,'Focused concept study — shape and relationship first; colour remains exploratory.',17,'#555'),'</svg>']
(R/'concept-board.svg').write_text('\n'.join(board))
proof=['<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="680" viewBox="0 0 1440 680"><rect width="1440" height="680" fill="white"/>',t(40,55,'Lowercase n + monarch / visual checks',28)]
for i,(name,b,xf) in enumerate([('Normal',mono,''),('Reversed',mono.replace('#000000','#ffffff'),''),('Mirror',mono,'translate(256 0) scale(-1 1)'),('180°',mono,'rotate(180 128 128)'),('Small-size drawing',small,'')]):
 x=40+i*280
 if i==1:proof.append(f'<rect x="{x}" y="110" width="240" height="240" rx="50" fill="black"/>')
 proof += [f'<g transform="translate({x} 110) scale(.9375)"><g transform="{xf}">{b}</g></g>',t(x,390,name,19)]
proof += [im(16,100,450,128),t(260,485,'16 px sample enlarged 8×',20),t(260,525,'The letter survives; the butterfly becomes a small silhouette.',18,'#555'),t(260,560,'Monarch-specific markings are not retained at this size.',18,'#555'),'</svg>']
# Request pixelated rendering for the enlarged raster.
(R/'tests/visual-proof.svg').write_text('\n'.join(proof).replace('<image','<image style="image-rendering:pixelated"'))
