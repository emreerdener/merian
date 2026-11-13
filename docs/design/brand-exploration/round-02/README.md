# Naturebook logo exploration: round 02

7 November 2026. Unapproved concepts responding to feedback on the first round.

## Correction to the brief

The first round reduced the symbols until their natural character became
ambiguous. Rounded lettering, a book, and an abstract stone did not provide a
strong enough nature cue or a memorable identity. The user's feedback
establishes a clearer requirement: recognizable natural forms must contribute
directly to the silhouette.

The product research and constraints in [the original brief](../README.md) still
apply. This round preserves the three earlier candidates as historical work and
builds new candidates here. Nothing in the first round is treated as approved.

The new design criterion is: **recognizably alive before the explanation**.
Naturebook still spans identification, personal records, community, field trips,
and exploration. A single organism can serve as an identifier without pretending
to illustrate all of those features, but a plant-only or bird-only reading is an
explicit tradeoff.

## Three revised directions

### A: Fiddlehead N

A continuous N develops into an unfurling fern, with a coiled tip and two broad
leaflets. The letter and botanical silhouette share their right-hand stem.

This is the strongest continuation of the original organic-N direction because
it connects a recognizable natural form to the brand's initial. The fern's
coiled growth is a more specific cue than an isolated generic leaf. Its weakness
is that the botanical detail can feel ornamental or suggest a plant-only
product.

The next design decision would be whether to make the whole letter more
frond-like or keep the contrast between a clear initial and the growing
terminal. This is a promising direction, not a claim of a finished or uniquely
protectable mark.

### B: Fieldwing

A compact insect silhouette has sweeping forewings, quieter hindwings, and two
large carved openings. The study began under the name Field moth; Fieldwing is
more accurate for this intentionally generalized moth/butterfly form.

It supplies a direct nature cue with a balanced square footprint. The silhouette
survives reduction without antennae or wing-vein detail. Its weakness is the
familiarity of butterfly imagery and limited connection to the Naturebook name.
The paired openings can also suggest eyes when isolated from the full
silhouette.

### C: Curious wren

A stylized small bird has a cocked tail, a slightly downward-facing beak, and
one broad wing opening. The wing cut gives the compact body movement without
feather detail. It is a characterful symbol, not an anatomically exact species
drawing.

This is the warmest alternative and the most directly characterful. Its weakness
is a possible bird-identification or bird-only brand reading. It should not be
presented as expressing the entire feature set by itself.

## Research and construction

The installed logo-design library was searched for fern, butterfly, moth, and
exemplary bird subjects. The first three searches returned no matches; absence
from this library is not originality evidence. Bird references included Twitter
and Swift. Twitter's SVG was read to study contour economy and to avoid its
rising-flight silhouette. The wren here has a cocked tail, carved wing, and a
lowered beak. Prior-round GNOME, Khan Academy, and DreamHost references remain
useful comparisons for organic reduction and figure-ground clarity.

All drawing files use closed black-filled paths on a 256 × 256 viewBox. There is
no live text, embedded image, filter, stroke, gradient, or mask in a candidate.
The presentation board uses live type only for annotation, not as a wordmark.

### Recorded refinement passes

- V1: natural motifs established. The fern curl was tight, the insect's
  hindwings were overly round, and the bird's tail dominated its body.
- V2: enlarged the fern's negative space and curved its diagonal; flattened and
  balanced the hindwings; shortened the bird's tail, reduced its eye, and
  aligned its beak to a deliberate 45-degree edge.
- V3: centred the fern's overall bounds, softened the insect's forewing tips,
  and raised the bird 10 units for better placement within the square.
- Small-size N: removed the inner spiral lobe in favour of one open rolled-tip
  counter. Used at 16 and 32 pixels; the full curl remains in the 64-pixel and
  larger studies. This is explicitly a different small-size drawing, not a claim
  that the full curl retains all detail at 16 pixels.

## Evidence and limits

The initial V1 render was blocked when automatic approval review could not run
because of a usage limit. The user's retry succeeded. Local headless Chrome was
used for the rendered studies.

V1, V2, V3, the small-size comparison, the final comparison board, and the
visual proof sheet were rendered and visually inspected. Actual 16 × 16, 32 ×
32, and 64 × 64 PNGs are saved in `renders/`. The board embeds these at their
native pixel dimensions; view the original at 100% because chat can scale the
whole image.

- N: readable initial at each size. The rolled-tip cut retains an open counter
  at 16 pixels; the full-size inner curl is deliberately omitted there.
- Fieldwing: recognizable insect outline at each size. Interior openings reduce
  to simple bright marks at 16 pixels.
- Wren: bird silhouette survives at each size. The eye is secondary and loses
  prominence at 16 pixels; recognition depends on the outline and wing opening.
- Reversal, mirroring, 180-degree rotation, and squint checks are in the proof
  sheet. Reversal uses the same geometry for comparison; a dedicated optical
  reverse master has not been developed.

The installed structural auditor reports no issues for the four final SVG
studies (including the small-size N), each scoring 100/100 on its heuristic.
That score checks file construction, not design quality or trademark clearance.

No independent audience-recognition test, trademark clearance, physical device
review, colour system, wordmark, or identity kit is included. Production app
assets, configuration, and code remain untouched. No commit, push, or
publication is part of this exploration.

## Files and next decision

- [Comparison board](comparison-board.png).
- [Visual proof](tests/visual-proof.png).
- [Fiddlehead N](concepts/a-fiddlehead-n.svg) and its
  [small-size cut](concepts/a-fiddlehead-n-small.svg).
- [Fieldwing](concepts/b-fieldwing.svg).
- [Curious wren](concepts/c-curious-wren.svg).
- `iterations/`: all meaningful drawing passes.
- `tests/audit-final.txt`: structural audit results.
- `build.py` and `present.py`: reproducible local drawings and presentation.

A is the strongest direction to develop for the name/nature connection. C offers
the most personality. The next checkpoint asks whether these recognizable
natural forms are closer to the intended identity, and which deserves further
refinement.
