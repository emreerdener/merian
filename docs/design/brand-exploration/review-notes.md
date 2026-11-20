# Candidate review and validation

6 November 2026. All three candidates remain unapproved.

## Construction and refinement

Every candidate uses a 256 × 256 viewBox, a single black fill, and closed paths.
No candidate contains live text, strokes, images, gradients, filters, masks, or
clipping. Clearing uses an even-odd compound path for a genuine transparent
hole. The nominal construction module is 2 units; controlled Bézier curves
supply the organic contours rather than a decorative circular grid.

### A: Living N

A single continuous contour forms two 44-unit stems with a flowing diagonal.
Tapered outside terminals oppose one another; the upper-left and lower-right
shoulders remain rounded. The diagonal is the living part of the letter, rather
than a leaf attached to it. The drawing has 180-degree rotational balance.

- V1: straight diagonal, hard inner junctions, and narrow terminal points.
- V2: a curved diagonal replaces the straight segment; longer terminals give
  movement, while the vertical stems preserve N recognition.
- V3: small quadratic transitions soften the inner corners and terminal tips.
  They remove sharp cusps without rounding the whole mark into a capsule.

The final structural audit counts 17 anchors. Approximate visible bounds are 172
× 177.4 units. This is roughly 67% of the tile width; the mark retains its own
clear space inside the square.

**Strength:** strongest name connection, legibility, and visual signature of the
three. **Risk:** an N is a crowded starting point; nature comes from its
sculpted character rather than an immediately identifiable subject.

### B: Fieldfold

Two filled contours form unequal pages. The taller right page gives lift; the
slightly concave outside edges suggest a book in a breeze. The open gutter is
structural negative space rather than a thin white line.

- V1: flat outer edges made the book static and conventional.
- V2: curved outside edges gave the spread movement and a more living
  silhouette.
- V3: the gutter widened from 22 to 26 units; the exposed tips and bottom
  corners received small curve transitions. The width corresponds to about 1.6
  pixels on the 16-pixel canvas and remains visibly separated.

The final structural audit counts 16 anchors across two contours. There are no
page rules or decorative details to disappear.

**Strength:** immediate connection between discovery and keeping a personal
record. **Risk:** book logos are common, and the mark may imply a reader or an
educational publisher before a nature-exploration app. At 16 pixels its subtle
curved edges lose much of their personality, although the book remains clear.

### C: Clearing

One river-worn outer contour encloses a smaller, asymmetrical window. The hole
is shaped independently from the outside, avoiding the uniform weight of a typed
O. This is an abstract invitation to look through or look closer, not an
organism illustration. The outer form sits slightly above the geometric centre.

- V1: an enclosed seed created a target/eye reading and a tight secondary gap.
  Rejected after viewing the large and reduced render.
- V2: removed the seed entirely. The pointed contour became too droplet-like.
- V3: rounded the apex into a river-stone contour and changed the inner oval to
  an irregular, bent opening. One opening is enough; no inner dot remains.

The final structural audit counts 12 anchors. The hole is open at all tested
sizes. This is the most abstract option and the one most dependent on repeated
brand exposure.

**Strength:** calm, tactile, language-independent, and broad enough to cover the
whole product. **Risk:** O, stone, bean, or wellness readings remain possible;
it has the weakest immediate connection to the Naturebook name.

## Visual checks actually performed

The installed skill's renderer initially failed inside the sandbox. It succeeded
using local headless Chrome outside the sandbox. The images listed below were
opened and visually inspected, not merely generated.

1. `tests/geometry-v1.png`: initial shapes, reversals, and 64/32/16 scale
   ladder.
2. `tests/geometry-v2.png`: first refinement pass, same comparisons.
3. `tests/geometry-v3.png`: second refinement pass, final drawings.
4. `research/reference-audit.png`: current iOS/web artwork, competitor examples,
   and the five construction references.
5. `tests/visual-proof.png`: final normal/reversed, mirror, 180-degree rotation,
   squint blur, circular crop, actual 16-pixel raster enlarged by
   nearest-neighbor display, peer comparison, and competitor shelf.
6. `comparison-board.png`: presentation layout, labels, spacing, clipping,
   rationale, recommendation, and true-size raster samples.

Actual 16 × 16, 32 × 32, and 64 × 64 PNGs were rendered separately for each
mark, with no additional renderer padding. The comparison board embeds those
files at native pixel dimensions. Screen or chat scaling can resize the board;
inspect the original PNG at 100% for an exact physical-pixel comparison.

| Check               | Living N                               | Fieldfold                               | Clearing                                       |
| ------------------- | -------------------------------------- | --------------------------------------- | ---------------------------------------------- |
| 16 px silhouette    | N remains clear                        | Book remains clear; subtle bends reduce | Open ring remains clear; O ambiguity increases |
| 32 px               | Flowing diagonal visible               | Gutter and unequal pages clear          | Irregular opening visible                      |
| 64 px               | Terminal and junction shaping visible  | Curved edges clearly visible            | River-stone asymmetry visible                  |
| One colour          | Pass                                   | Pass                                    | Pass                                           |
| Reversed            | Readable; white looks slightly heavier | Open gutter survives                    | Hole stays open                                |
| Mirror / 180°       | Balanced; mirrored N is expected       | No concerning reading observed          | No concerning reading observed                 |
| Squint              | Strong N skeleton                      | Two-page silhouette                     | Strong ring; weakest semantic specificity      |
| Circular crop       | Fits                                   | Fits                                    | Fits                                           |
| Junction inspection | No seams or slivers observed           | Separate contours, no overlaps          | Genuine hole, no overpaint                     |

These are designer judgments from renders, not independent audience testing.
White reversal uses the same geometry for first-round comparison. A dedicated
optically thinned reverse master, colour testing, physical device checks, and
platform-specific production exports would follow concept approval.

## Structural verification

The installed `svg_audit.py` reported no issues for all three passes. Each final
mark received its heuristic 100/100 score: one colour, no raster/filter/text,
and low complexity. The score does not establish originality, trademark
clearance, or production approval. Logs are in `tests/audit-v1.txt`,
`audit-v2.txt`, and `audit-v3.txt`.

The XML structure of every candidate and saved iteration was parsed, and the
exact dimensions of all nine size-test PNGs were checked. Markdown was formatted
with `deno fmt` and checked afterward. No application, backend, or CI tests were
run because no implementation files changed.

## Recommendation and next decision

Develop **A, Living N**. It is the strongest small symbol and connects directly
to the name without limiting Naturebook to identification, plants, or
journaling. It also carries the desired organic quality with one continuous
silhouette.

B is the strongest alternative if the personal record should lead the brand. C
is the more abstract alternative if a quiet natural object should lead, but it
needs the most work to become recognizably Naturebook.

Feedback should identify the preferred silhouette, the level of organic
softness, and whether the mark should express the name or a natural-world
metaphor. This round stops at that decision. A complete identity kit remains
unstarted.
