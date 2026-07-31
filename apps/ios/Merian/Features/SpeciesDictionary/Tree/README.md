# Species Dictionary Tree

The `Tree` directory contains the preserved UI and graph logic for navigating
the Linnaean taxonomy tree.

## MVP release status

Tree/galaxy visualization is deferred beyond MVP. No production or simulator
Explore navigation entry exposes this area. The source, `/species-dictionary`
`mode: "tree"` support, internal taxonomy route, and default-off
`.speciesDictionaryTree` feature flag remain intact so the work can resume
without recreating its data contract.

Do not add an Index header control, bottom tab, overview card, deep-link route,
or other user entry point until the future release criteria in
`docs/rfcs/species-dictionary-long-term-todo.md` are complete. The feature flag
is a release gate, not an authorization boundary.

## Structure

- **Views**: Tree visualization and navigation screens.
- **Models**: Data structures for representing hierarchical taxonomy nodes (Kingdom, Phylum, Class, Order, Family, Genus, Species).

## Purpose

This area is intended to let users explore species through taxonomic
relationships and understand how organisms relate within the tree of life. It
is retained for future development and is not part of the current MVP user
experience.
