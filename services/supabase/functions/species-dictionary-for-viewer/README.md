# Species dictionary for the authenticated viewer

Native dictionary detail, catalog and overview reads use this authenticated
route. The shared Edge wrapper supplies the viewer identity; request body
identity cannot override it. Request shapes, response shapes and schema version
1 match `species-dictionary`. Responses, including authentication failures, use
`Cache-Control: private, no-store` and `Vary: Authorization`.

The existing dictionary database implementation accepts a viewer ID and filters
normalized and legacy reference URLs with the service-only
`filter_reported_explore_media` RPC. It selects eligible alternatives while
retaining species with no eligible image. Filtering failures fail the request
closed. The anonymous sibling route keeps its public projection.

See the
[account visibility contract](../../../../docs/features-and-hardware/30-reported-content-visibility.md).
`handler_test.ts` verifies authentication, viewer propagation and cache headers;
`../species-dictionary/viewerMedia_test.ts` covers batched, fail-closed
filtering.
