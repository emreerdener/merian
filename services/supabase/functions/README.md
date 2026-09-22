# Edge Function directory guide

Use this index to find the current owner by product area. Each endpoint appears
once; a link opens its local README when available, otherwise its `index.ts`.
These groups are for navigation, not authentication classes or proposed route
renames. Route READMEs and the
[API contract](../../../docs/backend-and-data/05-api-contracts.md) remain
authoritative for caller permissions and behavior.

The
[Edge architecture](../../../docs/system-architecture/06-edge-modularization.md)
owns module responsibilities. The
[organization plan](../../../docs/rfcs/supabase-functions-organization.md)
records the measured dependency audit and future slices. Endpoint folders stay
at `functions/<endpoint>/`; the current discovery/configuration tools depend on
that layout.

## Find an endpoint

### Identification and enrichment

- [audio-spec](./audio-spec/README.md)
- [enrich-scan](./enrich-scan/README.md)
- [identify](./identify/README.md)
- [identify-describe](./identify-describe/README.md)
- [identify-multimodal](./identify-multimodal/README.md)
- [update-scan-context](./update-scan-context/README.md)

### Private library, capture, and scan recovery

- [auto-purge-nonbio](./auto-purge-nonbio/README.md)
- [check-scan-status](./check-scan-status/README.md)
- [delete-scan](./delete-scan/README.md)
- [generate-upload-urls](./generate-upload-urls/README.md)
- [ingest-r2-media-events](./ingest-r2-media-events/README.md)
- [reconcile-scan-deletions](./reconcile-scan-deletions/README.md)
- [reconcile-scan-media-assets](./reconcile-scan-media-assets/README.md)
- [repair-scan-image](./repair-scan-image/README.md)
- [replay-scan-ingestion](./replay-scan-ingestion/README.md)
- [scan-media-health](./scan-media-health/README.md)
- [sync-collections](./sync-collections/README.md)

### Explore publication, feeds, comments, and reactions

- [create-explore-comment](./create-explore-comment/index.ts)
- [delete-explore-comment](./delete-explore-comment/index.ts)
- [get-explore-author-posts](./get-explore-author-posts/README.md)
- [get-explore-author-profile](./get-explore-author-profile/README.md)
- [get-explore-comment-replies](./get-explore-comment-replies/index.ts)
- [get-explore-comments](./get-explore-comments/index.ts)
- [get-explore-composer-media](./get-explore-composer-media/README.md)
- [get-explore-feed](./get-explore-feed/README.md)
- [get-explore-hashtag-posts](./get-explore-hashtag-posts/README.md)
- [get-explore-map-points](./get-explore-map-points/README.md)
- [get-explore-mention-suggestions](./get-explore-mention-suggestions/README.md)
- [get-explore-post](./get-explore-post/index.ts)
- [get-explore-post-detail](./get-explore-post-detail/index.ts)
- [get-explore-post-reactors](./get-explore-post-reactors/README.md)
- [get-explore-reactions](./get-explore-reactions/README.md)
- [get-explore-species-posts](./get-explore-species-posts/README.md)
- [get-filtered-discovery-feed](./get-filtered-discovery-feed/README.md)
- [get-scan-explore-share-state](./get-scan-explore-share-state/README.md)
- [set-explore-comment-reaction](./set-explore-comment-reaction/README.md)
- [set-explore-post-like](./set-explore-post-like/index.ts)
- [set-explore-post-reaction](./set-explore-post-reaction/README.md)
- [share-scan-to-explore](./share-scan-to-explore/README.md)
- [toggle-explore-comment-reaction](./toggle-explore-comment-reaction/README.md)
- [unshare-explore-post](./unshare-explore-post/index.ts)
- [update-explore-field-notes](./update-explore-field-notes/README.md)

### Explore media maintenance

- [backfill-explore-audio-spectrograms](./backfill-explore-audio-spectrograms/README.md)
- [get-explore-media-incidents](./get-explore-media-incidents/README.md)
- [reconcile-explore-media-health](./reconcile-explore-media-health/README.md)

### Field Chat

- [explore-post-chat](./explore-post-chat/README.md)
- [insight-chat](./insight-chat/README.md)
- [species-dictionary-chat](./species-dictionary-chat/README.md)

### Community identification and taxonomy index

- [community-taxonomy-status](./community-taxonomy-status/README.md)
- [get-community-identification-activity](./get-community-identification-activity/README.md)
- [get-community-identification-detail](./get-community-identification-detail/index.ts)
- [get-community-identification-feed](./get-community-identification-feed/index.ts)
- [process-community-consensus-jobs](./process-community-consensus-jobs/index.ts)
- [request-community-identification](./request-community-identification/README.md)
- [restore-community-identification](./restore-community-identification/index.ts)
- [search-community-taxa](./search-community-taxa/README.md)
- [submit-community-feedback](./submit-community-feedback/index.ts)
- [submit-community-identification](./submit-community-identification/index.ts)
- [sync-community-taxonomy-index](./sync-community-taxonomy-index/README.md)
- [update-community-identification-request](./update-community-identification-request/index.ts)
- [withdraw-community-identification](./withdraw-community-identification/index.ts)

### Species dictionary, discovery, and reference content

- [refresh-merian-reference-images](./refresh-merian-reference-images/README.md)
- [refresh-species-content](./refresh-species-content/README.md)
- [refresh-species-model-content](./refresh-species-model-content/README.md)
- [refresh-taxonomy-nodes](./refresh-taxonomy-nodes/index.ts)
- [resolve-species-dictionary](./resolve-species-dictionary/README.md)
- [species-dictionary](./species-dictionary/README.md)
- [species-discovery-search](./species-discovery-search/README.md)
- [species-observation-stats](./species-observation-stats/README.md)

### Field trips

- [field-trips](./field-trips/README.md)

### Public profiles, following, and safety reports

- [block-user](./block-user/README.md)
- [check-public-username](./check-public-username/README.md)
- [flag-issue](./flag-issue/README.md)
- [report-explore-comment](./report-explore-comment/index.ts)
- [report-explore-post](./report-explore-post/README.md)
- [report-user](./report-user/README.md)
- [set-user-follow](./set-user-follow/README.md)
- [update-public-avatar](./update-public-avatar/README.md)
- [update-public-display-name](./update-public-display-name/index.ts)
- [update-public-username](./update-public-username/README.md)

### Account lifecycle

- [merge-ghost-profile](./merge-ghost-profile/README.md)
- [reconcile-account-deletions](./reconcile-account-deletions/README.md)
- [reconcile-ghost-profile-merges](./reconcile-ghost-profile-merges/README.md)
- [recover-account-deletion](./recover-account-deletion/README.md)
- [register-apple-revocation-token](./register-apple-revocation-token/README.md)
- [safe-delete](./safe-delete/README.md)

### Purchases and entitlements

- [expire-subscription-passes](./expire-subscription-passes/README.md)
- [reconcile-revenuecat-subscribers](./reconcile-revenuecat-subscribers/README.md)
- [resolve-purchase-principal](./resolve-purchase-principal/README.md)
- [revenuecat-webhook](./revenuecat-webhook/README.md)
- [transfer-signout-purchases](./transfer-signout-purchases/README.md)

### Notifications and feedback

- [get-explore-notifications](./get-explore-notifications/README.md)
- [get-explore-unread-notification-count](./get-explore-unread-notification-count/index.ts)
- [mark-explore-notifications-read](./mark-explore-notifications-read/index.ts)
- [register-push-device](./register-push-device/index.ts)
- [send-push-notification](./send-push-notification/README.md)
- [submit-feedback-survey](./submit-feedback-survey/index.ts)

### Darwin Core exports

- [download-dwca](./download-dwca/README.md)
- [export-dwca](./export-dwca/README.md)
- [reconcile-dwca-archive-cleanup](./reconcile-dwca-archive-cleanup/README.md)
- [request-export-dwca](./request-export-dwca/README.md)

## Shared owners

The existing [`_shared/ai/`](./_shared/ai/README.md) directory owns provider
contracts, explicit bindings, and execution; `_shared/identify/` owns common
identification rules and finalization helpers. See the
[shared-owner reference](./_shared/README.md) for their individual
responsibilities. [`_shared/fieldChat/`](./_shared/fieldChat/README.md) owns the
shared Field Chat prompt rules, native reply request/parser, admission, daily
usage, and response/replay helpers. Generated identity remains at the shared
root. The table below groups the remaining root TypeScript modules by their
current purpose; it does not claim these are already separate directories.
Shared media and authorization helpers have consumers across several endpoint
groups.

| Purpose                                             | Current root modules                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| HTTP, authentication, and neutral infrastructure    | [auth.ts](./_shared/auth.ts), [claimsAuth.ts](./_shared/claimsAuth.ts), [clientAddress.ts](./_shared/clientAddress.ts), [concurrency.ts](./_shared/concurrency.ts), [edgeHandler.ts](./_shared/edgeHandler.ts), [encoding.ts](./_shared/encoding.ts), [http.ts](./_shared/http.ts), [outbound.ts](./_shared/outbound.ts), [posthog.ts](./_shared/posthog.ts), [publishableKey.ts](./_shared/publishableKey.ts), [serviceRoleAuth.ts](./_shared/serviceRoleAuth.ts), [serviceRoleClient.ts](./_shared/serviceRoleClient.ts) |
| Gemini transport                                    | [gemini.ts](./_shared/gemini.ts)                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Identification and biological content               | [audioProcessing.ts](./_shared/audioProcessing.ts), [biology.ts](./_shared/biology.ts)                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| AI admission, allowance, and usage                  | [aiQuota.ts](./_shared/aiQuota.ts), [aiUsage.ts](./_shared/aiUsage.ts), [complimentaryScans.ts](./_shared/complimentaryScans.ts), [entitlement.ts](./_shared/entitlement.ts), [groupTagQuota.ts](./_shared/groupTagQuota.ts)                                                                                                                                                                                                                                                                                               |
| Media, storage, and reference-image policy          | [audioModeration.ts](./_shared/audioModeration.ts), [audioSpectrogram.ts](./_shared/audioSpectrogram.ts), [aws.ts](./_shared/aws.ts), [capturedMediaContract.ts](./_shared/capturedMediaContract.ts), [externalImagePolicy.ts](./_shared/externalImagePolicy.ts), [mediaBudgets.ts](./_shared/mediaBudgets.ts), [referenceImageRights.ts](./_shared/referenceImageRights.ts)                                                                                                                                               |
| Scan ingestion, persistence, recovery, and deletion | [scanIngestionCompatibility.ts](./_shared/scanIngestionCompatibility.ts), [scanIngestionIntents.ts](./_shared/scanIngestionIntents.ts), [scanIngestionJobs.ts](./_shared/scanIngestionJobs.ts), [scanIngestionRetry.ts](./_shared/scanIngestionRetry.ts), [scanMediaAssets.ts](./_shared/scanMediaAssets.ts), [scanMediaDeletion.ts](./_shared/scanMediaDeletion.ts), [scanPersistence.ts](./_shared/scanPersistence.ts), [scanRecovery.ts](./_shared/scanRecovery.ts)                                                     |
| Explore publication, filters, and reactions         | [explore.ts](./_shared/explore.ts), [exploreAudioTelemetry.ts](./_shared/exploreAudioTelemetry.ts), [exploreComposerMedia.ts](./_shared/exploreComposerMedia.ts), [exploreFeedFilters.ts](./_shared/exploreFeedFilters.ts), [explorePostMedia.ts](./_shared/explorePostMedia.ts), [exploreReactionDb.ts](./_shared/exploreReactionDb.ts), [exploreReactions.ts](./_shared/exploreReactions.ts)                                                                                                                             |
| Field Chat                                          | [fieldChatDeploymentIdentity.ts](./_shared/fieldChatDeploymentIdentity.ts)                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Species identity, content, and public projection    | [external.ts](./_shared/external.ts), [publicSpeciesProjection.ts](./_shared/publicSpeciesProjection.ts), [speciesContentProvenance.ts](./_shared/speciesContentProvenance.ts), [taxonomy.ts](./_shared/taxonomy.ts), [verifiedSpecies.ts](./_shared/verifiedSpecies.ts)                                                                                                                                                                                                                                                   |
| Community identification                            | [communityIdentification.ts](./_shared/communityIdentification.ts)                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Account lifecycle                                   | [accountDeletion.ts](./_shared/accountDeletion.ts), [appleSignIn.ts](./_shared/appleSignIn.ts)                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Purchases                                           | [revenueCatReconciliationHealthPolicy.ts](./_shared/revenueCatReconciliationHealthPolicy.ts), [revenuecatIdentity.ts](./_shared/revenuecatIdentity.ts), [subscriptionPass.ts](./_shared/subscriptionPass.ts)                                                                                                                                                                                                                                                                                                               |
| Darwin Core exports                                 | [dwcaReleaseState.ts](./_shared/dwcaReleaseState.ts)                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |

`_shared/emojiCatalog.json` is a generated runtime asset owned by the
[emoji catalog generator](../../../resources/emoji/README.md). Preserve its
asset imports and generator contract during any later move. Generated
`fieldChatDeploymentIdentity.ts` stays generator-owned as well.

## Tests, configuration, and tools

- Endpoint tests stay beside the code they exercise. Shared tests live beside
  their helper; `_tests/` contains cross-route, source-contract, migration, and
  database-concurrency coverage. Naming alone does not establish whether a test
  requires a disposable database.
- `deno.json` and `dependencies.lock` own the common dependency pins. Each
  endpoint's `deno.json` is generated by
  [`sync_function_deno_configs.ts`](../scripts/sync_function_deno_configs.ts).
- [`function_dependency_tools.ts`](../scripts/function_dependency_tools.ts)
  discovers the runtime import graphs used by validation and deploy selection.
  Tools and diagnostics belong in `../scripts/`; SQL catalog fixtures belong in
  `../tests/`.
- The
  [testing strategy](../../../docs/development-guides/08-testing-strategy.md)
  owns validation gates. After adding or retiring an endpoint, update this
  navigation index alongside the executable config/discovery contract.

## Preserve the AI validation handoff

The
[AI verification record](../../../docs/rfcs/identification-foundation-verification.md)
and
[provider-flexibility SRD](../../../docs/rfcs/identification-foundation-srd.md)
retain completed local evidence and outstanding candidate/hosted/device checks.
File organization does not enable another provider or clear those checks.
Historical benchmark source fingerprints continue to describe their original
revision; future changes need their own evidence where applicable.
