"""Reproducible drawings for Naturebook's first concept review; no app assets written."""
from pathlib import Path
from html import escape
ROOT = Path(__file__).resolve().parent

def svg(name, body):
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256" role="img" aria-label="{name}">\n<title>{name} — Naturebook exploration</title>\n{body}\n</svg>\n'

# Sculpted continuous N: two 44-unit stems, tapered terminals, rounded diagonal joins.
A1 = '<path fill="#000000" d="M44 214V75C44 54 57 42 76 42C88 42 98 48 107 60L168 147V83C168 60 183 44 212 42V181C212 202 199 214 180 214C168 214 158 208 149 196L88 109V173C88 196 73 212 44 214Z"/>'
# Two unequal pages. Curved outside edges and a generous open central gutter.
B1 = '<path fill="#000000" d="M36 60C74 60 104 78 117 105V211C96 189 69 178 36 178Z M139 105C156 76 184 54 220 42V162C187 170 158 189 139 211Z"/>'
# An asymmetric clearing with an offset seed. Broad enclosing rim, no camera blades.
C1 = '<path fill="#000000" fill-rule="evenodd" d="M128 34C182 30 221 65 225 119C229 174 189 218 136 222C82 226 38 195 32 144C26 90 73 39 128 34Z M139 76C105 76 74 106 74 139C74 165 93 183 119 183C153 183 183 153 183 120C183 94 165 76 139 76Z"/><path fill="#000000" d="M148 102C165 102 176 112 176 127C176 147 160 162 139 162C124 162 115 152 115 139C115 119 130 102 148 102Z"/>'
for letter,name,body in [('a','Living N',A1),('b','Fieldfold',B1),('c','Clearing',C1)]:
    (ROOT/'iterations'/f'{letter}-v1.svg').write_text(svg(name,body))

# Initial review sheet: large black, reversed, and honest unscaled pixel ladders.
def sheet(version, bodies):
    out=['<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="900" viewBox="0 0 1440 900">', '<rect width="1440" height="900" fill="white"/>']
    out.append('<g font-family="Helvetica,Arial,sans-serif" fill="#000">')
    out.append(f'<text x="50" y="60" font-size="28">Naturebook · geometry review {version}</text>')
    for i,(name,body) in enumerate(bodies):
        x=40+i*470
        out.append(f'<text x="{x+16}" y="120" font-size="22">{escape(name)}</text>')
        out.append(f'<g transform="translate({x+52} 155) scale(1.4)">{body}</g>')
        out.append(f'<rect x="{x+20}" y="550" width="160" height="160" rx="35" fill="black"/>')
        out.append(f'<g transform="translate({x+20} 550) scale(.625)">{body.replace("#000000","#ffffff")}</g>')
        for j,s in enumerate([64,32,16]):
            xx=x+226+j*80
            out.append(f'<g transform="translate({xx} 605) scale({s/256})">{body}</g><text x="{xx}" y="710" font-size="13">{s}px</text>')
    out.append('</g></svg>')
    (ROOT/'tests'/f'geometry-{version}.svg').write_text('\n'.join(out))
sheet('v1',[('A / Living N',A1),('B / Fieldfold',B1),('C / Clearing',C1)])

# Refinement one: flowing N diagonal; wind-bent page edges; remove target-like inner dot.
A2 = '<path fill="#000000" d="M42 217V84C42 57 53 43 72 43C94 43 109 67 124 94C141 123 153 142 170 150V84C170 57 184 43 214 39V172C214 199 203 213 184 213C162 213 147 189 132 162C115 133 103 114 86 106V172C86 199 72 213 42 217Z"/>'
B2 = '<path fill="#000000" d="M36 60C74 60 104 78 117 105V211C96 189 69 178 36 178C48 145 48 100 36 60Z M139 105C156 76 184 54 220 42C208 77 204 121 210 158C182 170 158 189 139 211Z"/>'
C2 = '<path fill="#000000" fill-rule="evenodd" d="M42 146C42 88 90 48 175 38C207 80 220 121 204 164C189 205 147 223 102 211C64 202 42 179 42 146Z M93 141C93 166 111 182 133 177C159 171 173 148 173 123C173 104 160 91 141 94C115 98 93 120 93 141Z"/>'
for letter,name,body in [('a','Living N',A2),('b','Fieldfold',B2),('c','Clearing',C2)]:
    (ROOT/'iterations'/f'{letter}-v2.svg').write_text(svg(name,body))
sheet('v2',[('A / Living N',A2),('B / Fieldfold',B2),('C / Clearing',C2)])

# Study-only reference board; trademarks remain the property of their owners.
import base64
LIB = Path('/Users/emreerdener/.codex/skills/logo-design/assets/library/svg')
def img(path,x,y,w,h):
    typ='image/svg+xml' if path.suffix=='.svg' else 'image/png'
    return f'<image x="{x}" y="{y}" width="{w}" height="{h}" href="data:{typ};base64,{base64.b64encode(path.read_bytes()).decode()}"/>'
board=['<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="1060" viewBox="0 0 1440 1060"><rect width="1440" height="1060" fill="white"/><g font-family="Helvetica,Arial,sans-serif" fill="black">', '<text x="40" y="55" font-size="28">Naturebook · reference audit / study only</text>']
repo=ROOT.parents[2]
for i,(title,path) in enumerate([('Current iOS',repo/'apps/ios/Merian/Assets.xcassets/App/AppIcon.appiconset/icon1024.png'),('Current web',repo/'apps/web/public/assets/logo.png'),('PictureThis',ROOT/'research/picturethis-icon.png')]):
    x=40+i*300
    board += [img(path,x,90,190,190),f'<text x="{x}" y="315" font-size="18">{title}</text>']
    for j,s in enumerate([64,32,16]): board.append(img(path,x+j*90,340,s,s))
board += [img(ROOT/'research/seek-reference.png',940,100,450,260),'<text x="940" y="400" font-size="18">Seek / official promotional artwork</text>']
board += ['<text x="40" y="490" font-size="24">Construction references · not competitors</text>']
for i,(name,lesson) in enumerate([('pagekit','Open counter'),('doctrine','Figure / ground'),('gnome-icon','Organic reduction'),('dreamhost','Offset masses'),('khan_academy-icon','Double reading')]):
    x=40+i*280
    board += [img(LIB/(name+'.svg'),x,550,170,200),f'<text x="{x}" y="795" font-size="19">{name}</text>',f'<text x="{x}" y="826" font-size="16">{lesson}</text>']
board += ['<text x="40" y="940" font-size="20">Keep: organic warmth, curiosity, strong silhouettes. Avoid: literal leaves, scanner frames, species collages.</text>','<text x="40" y="990" font-size="15">Reference artwork is shown for comparison only. Sources and limits are recorded in README.md.</text></g></svg>']
(ROOT/'research/reference-audit.svg').write_text('\n'.join(board))

# Refinement two: soften N junctions; widen book gutter; replace the droplet apex with a river-worn contour.
A3 = '<path fill="#000000" d="M44 216.7Q42 217 42 215V84C42 57 53 43 72 43C94 43 109 67 124 94C139 120 152 140 166 148Q170 150 170 146V84C170 58 183 44 212 39.3Q214 39 214 41V172C214 199 203 213 184 213C162 213 147 189 132 162C117 136 104 116 90 108Q86 106 86 110V172C86 198 73 212 44 216.7Z"/>'
B3 = '<path fill="#000000" d="M39 60C74 61 103 78 115 105V207Q115 211 112 208C91 189 66 178 39 178Q35 178 36 174C47 142 47 103 36 64Q35 60 39 60Z M141 105C157 78 184 56 216 44Q220 42 219 46C208 80 204 121 210 156Q211 159 208 160C183 172 160 189 144 208Q141 211 141 207Z"/>'
C3 = '<path fill="#000000" fill-rule="evenodd" d="M121 37C158 29 195 43 210 75C226 109 217 149 190 181C164 212 124 224 88 212C53 201 34 173 37 139C40 100 79 46 121 37Z M128 86C146 79 163 88 166 106C169 124 158 136 147 151C135 168 124 176 109 170C92 163 88 149 94 132C100 114 111 93 128 86Z"/>'
FINAL=[('a','Living N',A3),('b','Fieldfold',B3),('c','Clearing',C3)]
for letter,name,body in FINAL:
    (ROOT/'iterations'/f'{letter}-v3.svg').write_text(svg(name,body))
    (ROOT/'concepts'/f'{letter}-{name.lower().replace(" ","-")}.svg').write_text(svg(name,body))
sheet('v3',[(f'{letter.upper()} / {name}',body) for letter,name,body in FINAL])

# Comparison board is presentation artwork; its live text is not part of any mark.
def text(x,y,content,size=18,fill='#000000',family='Helvetica,Arial,sans-serif',weight='400'):
    return f'<text x="{x}" y="{y}" font-family="{family}" font-size="{size}" font-weight="{weight}" fill="{fill}">{escape(content)}</text>'

def lines(x,y,items,size=18,fill='#333333',step=27):
    return '\n'.join(text(x,y+j*step,line,size,fill) for j,line in enumerate(items))

out=['<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1240" viewBox="0 0 1600 1240">', '<rect width="1600" height="1240" fill="#ffffff"/>']
out += [text(64,55,'NATUREBOOK / SYMBOL STUDIES',14,'#555555',weight='600'),text(1270,55,'06 NOVEMBER 2026',14,'#555555'),text(64,122,'A life of noticing.',52,family='Georgia,serif'),text(64,165,'Three directions for curiosity, personal discovery, and a lasting connection with nature.',21,'#444444'),'<path d="M64 197H1536" stroke="#222222"/>']
notes=[
    ('LETTERFORM', ['A continuous N with a flowing diagonal', 'and two gently tapered terminals.'], ['Direct connection to the name.', 'Distinctive silhouette; strongest at 16 px.'], ['Nature is suggested through form,', 'rather than a literal natural subject.']),
    ('PICTORIAL ABSTRACTION', ['An open fieldbook with pages that bend', 'as if caught by a passing breeze.'], ['Connects discovery with keeping a record.', 'Warm, editorial, and easy to understand.'], ['Book marks are a crowded territory;', 'may suggest reading before exploring.']),
    ('ABSTRACT SYMBOL', ['A river-worn opening in a smooth stone:', 'a small invitation to look more closely.'], ['Tactile, quiet, and independent of language.', 'Leaves room for every kind of encounter.'], ['May read as an O or a wellness symbol;', 'needs more brand association to be owned.'])]
for i,((letter,name,body),(typ,idea,strength,risk)) in enumerate(zip(FINAL,notes)):
    x=64+i*504
    if i: out.append(f'<path d="M{x-24} 226V1065" stroke="#dedede"/>')
    out += [text(x,245,f'{letter.upper()} / {name}',29,family='Georgia,serif'),text(x,276,typ,12,'#666666',weight='600')]
    if i==0: out += ['<rect x="365" y="224" width="151" height="27" rx="13.5" fill="black"/>',text(382,242,'RECOMMENDED',11,'white',weight='600')]
    out += [f'<g transform="translate({x+69} 310) scale(1.25)">{body}</g>']
    out += [f'<rect x="{x}" y="656" width="112" height="112" rx="25" fill="#000000"/>', f'<g transform="translate({x} 656) scale(.4375)">{body.replace("#000000","#ffffff")}</g>',text(x,791,'REVERSED / TILE STUDY',10,'#555555')]
    for j,s in enumerate([64,32,16]):
        xx=x+174+j*98
        p=ROOT/'renders'/str(s)/f'{letter}-{name.lower().replace(" ","-")}.png'
        if p.exists(): out.append(img(p,xx,696+(64-s)/2,s,s))
        else: out.append(f'<g transform="translate({xx} {696+(64-s)/2}) scale({s/256})">{body}</g>')
        out.append(text(xx,791,f'{s} px',12,'#555555'))
    out += [lines(x,839,idea,18),text(x,914,'STRENGTH',11,'#555555',weight='600'),lines(x,942,strength,17),text(x,1014,'TRADEOFF',11,'#555555',weight='600'),lines(x,1042,risk,17)]
out += ['<path d="M64 1106H1536" stroke="#222222"/>',text(64,1148,'Start with A — Living N.',27,family='Georgia,serif'),text(64,1185,'The clearest name connection, with enough organic character to grow into a broader identity.',19,'#444444'),text(1300,1185,'EXPLORATION / 01',12,'#555555'),'</svg>']
(ROOT/'comparison-board.svg').write_text('\n'.join(out))

# Compact visual proof: actual rasters, reversals, transformations, crops, and peers.
qa=['<!doctype html><html><head><meta charset="utf-8"><title>Naturebook visual checks</title><style>*{box-sizing:border-box}body{margin:0;padding:38px;background:white;color:black;font-family:Helvetica,Arial,sans-serif;width:1600px}h1{font-size:30px;margin:0 0 12px}p{color:#555}section{display:flex;align-items:center;gap:32px;border-top:1px solid #ccc;padding:22px 0}.label{width:130px}.test{text-align:center;width:148px;font-size:12px}.test>div{height:130px;display:flex;align-items:center;justify-content:center}.test svg{width:104px;height:104px}.dark{background:#000;border-radius:24px;width:112px;margin:auto}.crop{border-radius:50%;background:#eee;width:112px;overflow:hidden;margin:auto}.pixel{image-rendering:pixelated;width:128px;height:128px}.peers{display:flex;gap:44px;align-items:end;padding:24px 0}.peer{width:130px;text-align:center;font-size:13px}.peer svg,.peer img{display:block;width:64px;height:64px;object-fit:contain;margin:0 auto 15px}.shelf .peer svg{filter:grayscale(1)}h2{font-size:19px;margin:18px 0 5px}</style></head><body><h1>Naturebook / visual proof</h1><p>Final candidate geometry. Pixel enlargement uses the actual 16 × 16 PNG; all artwork is black and white.</p>']
for letter,name,body in FINAL:
    inline=svg(name,body)
    png=(ROOT/'renders/16'/f'{letter}-{name.lower().replace(" ","-")}.png')
    data=base64.b64encode(png.read_bytes()).decode() if png.exists() else ''
    qa += [f'<section><div class="label"><b>{letter.upper()} / {name}</b></div>']
    cases=[('Normal',inline),('Reversed',f'<div class="dark">{inline.replace("#000000","#ffffff")}</div>'),('Mirror',inline.replace('<path','<path transform="translate(256 0) scale(-1 1)"')),('180°',inline.replace('<path','<path transform="rotate(180 128 128)"')),('Squint blur',f'<span style="filter:blur(3px)">{inline}</span>'),('Circle crop',f'<div class="crop">{inline}</div>'),('16 px × 8',f'<img class="pixel" src="data:image/png;base64,{data}">')]
    for label,content in cases: qa.append(f'<div class="test"><div>{content}</div><p>{label}</p></div>')
    qa.append('</section>')
qa += ['<h2>Peer construction check / equal 64 px viewports</h2><div class="peers shelf">']
for letter,name,body in FINAL: qa.append(f'<div class="peer">{svg(name,body)}{name}</div>')
for name in ['pagekit','gnome-icon','dreamhost','khan_academy-icon']:
    qa.append(f'<div class="peer">{(LIB/(name+".svg")).read_text()}{name}</div>')
qa += ['</div><h2>Category shelf / references are trademarks of their owners</h2><div class="peers">']
for letter,name,body in FINAL: qa.append(f'<div class="peer">{svg(name,body)}{name}</div>')
for name,p in [('Current iOS',repo/'apps/ios/Merian/Assets.xcassets/App/AppIcon.appiconset/icon1024.png'),('PictureThis',ROOT/'research/picturethis-icon.png')]:
    data=base64.b64encode(p.read_bytes()).decode();qa.append(f'<div class="peer"><img src="data:image/png;base64,{data}">{name}</div>')
# Show the Seek leaf from its official promotional image, without tracing or redrawing.
data=base64.b64encode((ROOT/'research/seek-reference.png').read_bytes()).decode()
qa += [f'<div class="peer"><svg viewBox="500 230 220 180" style="background:#36996d"><image width="2000" height="842" href="data:image/png;base64,{data}"/></svg>Seek (reference)</div></div><p>Visual screening only. No trademark clearance or independent audience-recognition test has been performed.</p></body></html>']
(ROOT/'tests/visual-proof.html').write_text('\n'.join(qa))
