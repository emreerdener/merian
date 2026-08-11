# SwiftData Schema Compatibility Pointer

Use `$merian-swiftdata-migrations` for every SwiftData model or schema-version
change. Its canonical workflow freezes the outgoing schema before active-model
edits, preserves historical model identities, adds the migration stage, and
verifies fresh-store and upgrade recovery.

Read the canonical instructions in
[`skills/merian-swiftdata-migrations/SKILL.md`](../../skills/merian-swiftdata-migrations/SKILL.md).
This compatibility file intentionally contains no independent migration steps.
