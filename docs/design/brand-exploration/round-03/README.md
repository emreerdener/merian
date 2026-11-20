# Lowercase n with a monarch

7 November 2026. Focused, unapproved concept study requested after round 02.

## Direction

A custom lowercase **n** supports a monarch poised over its right shoulder. The
letter has a wide counter and gently curved foot terminals. A small gap keeps
the butterfly's lower wing from merging into the letter. The butterfly sits at a
15-degree angle, giving the otherwise stable letter some movement.

This responds directly to the requested pairing. The previous fern, insect, and
bird alternatives are preserved; this round does not develop a complete identity
kit or change any app assets.

## Monarch reference and simplification

The
[US Fish and Wildlife Service monarch reference](https://www.fws.gov/species/monarch-danaus-plexippus)
describes orange wings with black veins, dark borders, and pale border spots.
The study reduces those cues to broad wing cells and four visible border spots.
The silhouette and markings are stylized; this is not an anatomical
identification illustration or a reproduction of the monarch's complete
vein/spot pattern.

The monochrome drawing was developed first. A muted orange (`#C96B26`) is shown
as an optional colour study to make the monarch association easier to judge. It
is not an approved brand palette. The reference-library butterfly query returned
no results; that does not establish originality or trademark availability.

## Refinement and size behavior

- Initial study: three closely related butterfly sizes and placements above the
  same n, to assess their relationship rather than offer unrelated concepts.
- First refinement: reduced the butterfly slightly, improved separation, and
  removed two trial border counters that extended outside the silhouette.
- Geometry refinement: softened the n's exposed terminals, baked all transforms
  into the vector coordinates, improved square placement, and aligned the paired
  hindwing-cell edges before the common rotation.
- Small-size cut: removes antennae, border spots, and secondary wing cells. Used
  at 16 and 32 pixels; the fuller pattern is shown at 64 pixels and larger.

The **n** remains readable at the tested sizes. At 16 pixels the butterfly is a
small silhouette; monarch-specific detail does not survive. The simplified cut
preserves the pairing rather than pretending to retain all of the markings.
Further reduction could require a more integrated wing/letter construction.

## Checks

The V1, V2, and V3 geometry sheets, final board, and visual proof were rendered
with local Chrome and inspected. The proof includes reversal, mirroring,
180-degree rotation, the simplified drawing, and an enlarged actual 16-pixel
raster. Exact 16 × 16, 32 × 32, and 64 × 64 samples are in `renders/`.

All three candidate SVGs use closed filled paths, genuine transparent counters,
a 256 × 256 viewBox, and no font dependency, strokes, gradients, masks, or
embedded rasters. Transforms are baked into the path coordinates.

The structural audit flags the full pattern's four small border spots, as
expected. The dedicated small drawing removes them. The audit reports no issues
for the small drawing. These are file checks and visual assessments, not
independent recognition testing or trademark clearance.

## Artifacts

- [Concept board](concept-board.png).
- [Monochrome SVG](concepts/n-monarch-mono.svg).
- [Orange study SVG](concepts/n-monarch-color-study.svg).
- [Small-size SVG](concepts/n-monarch-small.svg).
- [Visual proof](tests/visual-proof.png).
- [Structural audit](tests/audit-final.txt).
- `iterations/`: saved geometry passes.
- `build.py`, `present.py`: reproducible drawing and presentation sources.

The next decision is whether the lowercase n and poised monarch relationship is
right, before refining the butterfly further or developing any identity system.
