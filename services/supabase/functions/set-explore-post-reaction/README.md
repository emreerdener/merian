# set-explore-post-reaction

Authenticated post emoji reactions. `index.ts` validates a bounded request and
uses the viewer from the shared Edge handler; `db.ts` delegates to the shared
reaction data adapter. Database RPCs enforce authorization and target
visibility.

See the
[canonical reaction API](../../../../docs/backend-and-data/05-api-contracts.md#explore-emoji-reactions-2026-09-18)
for request/response shapes, Unicode validation, pagination, and compatibility.

Validation covers Unicode aliases, retry idempotence, permissions, activity
capabilities, and disposable database integration in `exploreReactions_test.ts`
and `exploreReactionsDb.test.ts`.
