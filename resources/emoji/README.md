# Explore emoji source data

`emoji-test-17.0.txt` is the pinned
[Unicode Emoji 17.0 dataset](https://www.unicode.org/Public/17.0.0/emoji/emoji-test.txt).
English names come from that dataset; additional search keywords use Unicode
CLDR release 48 annotations and derived annotations. `LICENSE.txt` retains
Unicode attribution and licensing; the app bundles a copy as
`ExploreEmojiUnicodeLicense.txt`.

Only fully-qualified emoji are canonical. Recognized minimally-qualified and
unqualified forms map to that identity. Skin tones, flags, and joined sequences
remain distinct; standalone components and arbitrary text are not reactions.
Picker cells render native emoji without visible name captions. Catalog names
remain available for search, accessibility, and help. The native picker filters
out skin-tone modifier sequences from its choices, including search results. The
full client/server catalog stays intact so existing toned reactions still
validate, display, and toggle independently.

## Maintenance

Run `python3 scripts/generate-explore-emoji-catalog.py` from the repository root
to generate identical iOS and Edge catalogs, or add `--check` to verify them
without writing. The generator does not rewrite the database seed.

The seed in `20260918142010_add_explore_emoji_reactions.sql` is an immutable
Unicode 17.0 snapshot. A future Unicode upgrade requires updating the pinned
source/attribution, regenerating both catalogs, and adding a new forward
database-catalog migration. Preserve existing canonical identities and review
ordering/cursor compatibility; never edit an applied migration to upgrade data.
The database integration parity test compares emoji, aliases, and order against
the generated catalog in addition to the generator drift check.

See the
[reaction API and rollout contract](../../docs/backend-and-data/05-api-contracts.md#reaction-rollout-order)
and
[verification matrix](../../docs/development-guides/08-testing-strategy.md#explore-emoji-reaction-verification).
