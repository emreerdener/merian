# Naturebook: first logo exploration

Date: 6 November 2026. Status: three unapproved design candidates. This folder
is an exploration, not a replacement brand contract or an app asset source.

The first-round candidates were not approved. The user found their natural
character and distinctiveness insufficient. See [round 02](round-02/README.md)
for the revised nature-led exploration. This document preserves the original
brief and first-round reasoning.

## Brief

**Design a memorable sign for a life of noticing nature.** It should feel grown,
observant, warm, and quietly accomplished. A square, text-free iOS symbol is the
primary use; recognition must survive black and white and 16, 32, and 64 pixels.

Naturebook connects curiosity, identification, a lasting personal record,
selective public sharing, community learning, and outings. The mark should span
that relationship without illustrating each feature. The audience ranges from
curious beginners and families to hobby naturalists and field participants.
Avoid both scientific-institution severity and children's-game cuteness.

The user is the design decision-maker. Organic N is a promising direction, not a
required final answer. No prior N artwork was located in the inspected
repository assets; this round develops a fresh construction from the stated
direction.

### Product evidence and boundaries

- [Master product document](../../product/01-master-product-document.md),
  sections 1, 2, 6, and 7: curiosity becomes a durable, contextual observation;
  private library, public Explore, community, Field trips, and personal
  achievements.
- [Journal brief](../../product/journal/brief.md): a private visual commonplace
  book for writing, drawing, collecting, and connecting knowledge. This is
  planning intent, distinct from the existing scan library and Field Notes.
- [Field trips](../../features-and-hardware/25-field-trips.md): guided outings,
  species discovery, and participation beyond a single identification.
- [Profile and gamification](../../features-and-hardware/06-profile-and-gamification.md):
  progression and achievement supply encouragement, not the entire identity.
- [Brand compatibility](../../system-architecture/08-public-brand-compatibility.md)
  and
  [rebrand runbook](../../development-guides/15-naturebook-rebrand-rollout.md):
  Naturebook is the public name; Merian remains the engineering identity.

This review uses repository files, including their current local edits, as the
product source. It does not claim all documented features are deployed. No
Notion content or production data was required.

## Existing visual audit

The light and dark iOS icons use a six-part natural-history ring: leaf,
butterfly wing, mushroom, feather, scale-like surface, and lobed leaf. Their
strengths are biodiversity, tactile detail, and affection for nature. Their
weaknesses are fine texture, multiple competing silhouettes, and a
camera-aperture reading. The identifying details collapse on reduction. White
and dark backgrounds are already part of the icon system.

The public web logo is a different green/teal interpretation of the same
circular collage. Its visual relationship is apparent, but it is not the same
drawing. The new exploration should establish a single reproducible silhouette.

The fern, compass, bird artwork, and Observer persona represent a soft, tactile,
three-dimensional illustration vocabulary. That warmth can inform a logo's
curves without importing the illustrations' detail or making a mascot mandatory.

### Colour and typography observed

- Web theme: forest scale from `#f2f8e9` to `#173c29`; primary light shade
  `#234d35`, dark shade `#bfdc91`.
- Web CSS: light neutral `#f5f5f3`, text `#222222`, dark background `#191919`,
  focus green `#315849`; system sans typography.
- iOS `AccentColor` has no explicit colour components in its JSON. The app root
  uses white tint; feature surfaces use semantic colours and selected coloured
  accents. There is no basis to call the web forest scale a unified iOS palette.
- Field-trip documentation specifies serif titles, giving an editorial cue that
  fits natural-history publishing. No wordmark or type system is proposed here.

Sources: `apps/web/app/theme.ts`, `apps/web/app/globals.css`,
`apps/ios/Merian/App/MerianApp.swift`,
`apps/ios/Merian/Assets.xcassets/App/AccentColor.colorset/Contents.json`,
`apps/ios/Merian/Assets.xcassets/App/AppIcon.appiconset/`,
`apps/web/public/assets/logo.png`, and the `Graphics3D` and `Personas` asset
groups.

Colour is deliberately withheld from candidate selection. Earthy character must
come from the shape before a green background is allowed to help it.

## Research and strategy

The installed logo-design library contains 1,432 SVG records. Its
organic-geometry search returned 197: 36% pictorial, 27.4% combination, and
15.7% mascot. It is technology-heavy, so these are construction references, not
a nature-market census. Subjects and negative-space techniques were searched
before drawing.

Five SVG constructions were read: Pagekit (one contour and an open counter),
Doctrine (figure-ground separation), GNOME (organic custom silhouette),
DreamHost (offset curved masses), and Khan Academy (plant/person double
reading). These teach economy, controlled curves, and counter spacing. They were
not traced. Khan Academy also argues against a book/sprout with a floating dot;
DreamHost argues against a simple crescent and disc. Spring, Envato, MongoDB,
and Leaflet show how crowded the literal-leaf territory is. Vaddy is an
additional ring-and-dot resemblance reference for the abstract direction.

Library searches included `--geometry organic --summary`, `--subject book`,
`--subject seed`, `--subject leaf`, `--subject eye`, and
`--technique negative-space --exemplary`. The narrow N subject query was poorly
indexed and did not establish originality.

### Competitor review

- [iNaturalist and Seek](https://help.inaturalist.org/en/support/solutions/articles/151000169914-what-is-the-difference-between-inaturalist-and-seek-by-inaturalist-):
  relevant overlaps in community observation and approachable exploration.
  [Seek's official artwork](https://www.inaturalist.org/pages/seek_app) uses a
  leaf/arrow, green field, and nature imagery. Avoid a leaf with a directional
  cut or a badge-led primary mark.
- [PictureThis](https://www.picturethisai.com/): its inspected official icon is
  a green flower inside four scanner corners. Avoid framing a plant as the
  primary brand idea; this would narrow Naturebook to a plant-identification
  utility.
- [Merlin](https://www.merlinbirds.org/download/): a relevant
  bird-identification comparison. The official download artwork could not be
  retrieved locally (HTTP 403), so no detailed visual judgment of its current
  icon is claimed.

The two downloaded official brand images in `research/` are study references,
owned by their respective brands. This is a focused visual screen, not trademark
clearance. Professional clearance and a broader reverse-image search belong
before adoption, after a direction is chosen.

The abstract concept was also checked against the library's ring-and-dot
references: its first target-like drawing was rejected during refinement. The
final stone has one irregular opening and no central dot.

### Off-limits conventions

Generic green leaves; magnifiers; scanner brackets; aperture blades; AI
sparkles; brain/circuit imagery; mountains plus sun; thin-line compass badges;
wreaths of species; a literal book with a sprout coming out of it.

### Word map

- Nature: growth, grain, stem, seed, shelter, variation, season.
- Book: memory, fold, gathering, margin, impression, return.
- Discovery: clearing, opening, encounter, attention, meander.
- Community: exchange, shared ground, many encounters, belonging.
- Desired tension: cultivated/wild; personal/shared; quiet/curious;
  simple/living.

Useful intersections: **growth + name**; **fold + living form**; **opening +
attention**. They lead to a letterform, a pictorial abstraction, and an abstract
symbol with different routes to recognition.

## Ten distinct conceptual approaches

Scores are exploratory judgments, 1–5, not user-test measurements. Columns are
clarity, distinction, simplicity, relevance, and expected small-size strength.

| Approach          | One-sentence concept                                                                                        | Scores    | Decision                                          |
| ----------------- | ----------------------------------------------------------------------------------------------------------- | --------- | ------------------------------------------------- |
| Living N          | A continuous N grows between two tapered terminals, like a naturally formed piece of lettering.             | 5/4/5/5/5 | Build A: strongest name ownership.                |
| Fieldfold         | Two unequal, gently turning pages give a fieldbook the lift of a living form.                               | 4/4/5/5/4 | Build B: record and discovery together.           |
| Clearing          | A river-worn stone encloses an irregular opening, turning a found object into an invitation to look closer. | 4/4/5/4/4 | Build C: strongest abstract alternative.          |
| Mycelial exchange | Three branching arms meet around one shared open space, suggesting knowledge assembled together.            | 3/3/3/5/3 | Reject: network/technology association.           |
| Encounter notch   | A single bite-like interruption in a pebble silhouette acts as the memory of an encounter.                  | 3/4/5/3/5 | Hold: meaning too dependent on explanation.       |
| Paired tracks     | Two unequal footprints encode outward exploration and a return to the personal record.                      | 4/3/4/4/4 | Reject: walking or fitness brand reading.         |
| Margin path       | One wandering cut enters a page-shaped block, turning a journal margin into a trail.                        | 4/3/4/5/4 | Hold: route/navigation emphasis.                  |
| Wayside cairn     | Three deliberately uneven stones form a quiet marker for accumulated encounters.                            | 4/3/5/4/5 | Hold: spa/outdoor-equipment resemblance.          |
| Seasonal hinge    | Two opposing seed cases pivot around a shared gap, expressing return and change.                            | 3/3/4/4/4 | Reject: yin-yang and generic wellness risk.       |
| Quiet witness     | A compact wren-like silhouette turns its head back toward the observer.                                     | 5/3/4/3/4 | Reject: bird-only promise and mascot competition. |

The selection balances concept strength with meaningful difference; it does not
simply choose three stylistic versions of the N.

## Review scope

Three vector symbols, recorded geometry iterations, monochrome/reversal and
small-size tests, and one comparison board. No production asset catalog changes,
configuration changes, commits, pushes, publication, lockups, or full identity
kit.

Next decision: select a direction or identify the qualities worth developing.
User approval is required before any complete identity kit.

## Artifacts

- [Comparison board](comparison-board.png): the three candidates, rationale,
  strengths, tradeoffs, recommendation, reverse tiles, and true-size samples.
- Vector candidates: [Living N](concepts/a-living-n.svg),
  [Fieldfold](concepts/b-fieldfold.svg), [Clearing](concepts/c-clearing.svg).
- [Visual proof](tests/visual-proof.png): actual raster enlargement, mirror,
  rotation, squint, crop, peer comparison, and category shelf.
- [Audit and refinement record](review-notes.md).
- [Existing brand and reference board](research/reference-audit.png).
- [Extended test sheet](tests/preview.html): generated with the installed skill.
- `iterations/`: all three saved construction passes.
- `renders/16`, `renders/32`, `renders/64`: exact-size transparent PNG tests.
- `build_exploration.py`: reproducible source for drawings and study boards.

The brief's phrase “a life of noticing” is an exploratory presentation theme,
not an approved tagline. Board typography uses local Georgia and Helvetica/Arial
for annotation only; the marks contain no text and depend on no fonts.
