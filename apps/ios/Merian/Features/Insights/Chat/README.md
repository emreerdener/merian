# Insight Chat

The `Chat` directory contains the logic and UI for the Pro-tier Field Chat
feature.

## Purpose

This area allows Pro users to ask contextual follow-up questions about a
completed biological scan without needing to re-upload raw images. It also
provides the shared presentation and floating control used by private per-viewer
chats on every visible Explore post, including the viewer's own posts. Insight
conversations use owner-only scan context; Explore conversations use only the
privacy-filtered public post and Species Dictionary projection. Both use Gemini
2.5 Flash and smart prompt chips.

Generated Insight prompt chips are merged with deterministic local fallbacks,
deduplicated, and filtered against pending or previously sent questions. For an
identification below 70% confidence, the three-chip result reserves a
confidence-category slot. An available server confidence prompt owns that slot
even when it arrives after three ordinary suggestions; otherwise the local
uncertainty fallback does. This prevents evidence, ecology, or seasonal
suggestions from crowding out the observation's uncertainty context.
Explore-post prompt chips do not use private scan confidence and retain their
separate public fallback behavior.

For Explore posts, the empty state uses the concise trust message
`This Field chat is private and visible only to you.` The conversation is never
shown to other viewers. Technical context limitations remain enforced by the
backend and documented in the API contract instead of being presented as
additional empty-state disclaimers.

## Owned Insight Readiness

Insight Field Chat depends on the exact authenticated-owner `public.scans` row;
a locally completed `LocalScanRecord` alone is not sufficient. The toolbar calls
`MerianNetworkClient.ensureCloudScanAvailableForFieldChat(scan:)` before it
presents `/insight-chat`.

The preflight:

1. polls `/check-scan-status` using the stable scan UUID;
2. returns immediately when the exact owner row is found;
3. leaves processing, finalizing, retrying, and retryable server ingestion under
   server ownership;
4. refuses known moderation, provider-safety, deletion, and ambiguous terminal
   state; and
5. for eligible historical drift only, builds a bounded non-media
   `OwnedScanRecoveryPayload`, submits it through single status recovery, and
   requires a final owner `found` response.

Recovery resolves the server species ID by scientific name and derives owner
from the current persisted Auth session. It never sends raw image/audio/video
bytes, local paths, object keys, direct cloud URLs, or a client-selected owner.
Field Chat does not restore or publish public media.

If status remains transiently unavailable, the button stays available for a
later retry and the user sees:

`This observation is still syncing. Please try Field chat again in a moment.`

Do not cache this result as permanent unavailability. A current Identify `200`
followed by this preflight returning missing is a severity incident because
durable owner read-back is part of Identify success.

Video owner readiness follows the canonical media timeline: one ready playback
clip and its poster, not separate ready image rows for sampled inference frames
retained in compatibility storage. The client does not manufacture frame media
to make Field Chat available; backend finalization migration
`20260729012153_fix_video_scan_canonical_finalization.sql` restores the shared
completed prerequisite while keeping Field Chat context text-only.

Platform route failure is distinct from a handler-owned missing scan.
`MerianError.edgeFunctionUnavailable` uses temporary service-unavailable copy
and must not enter owner-row recovery.

## Context and Privacy

Owned Insight chat uses only saved owner text evidence. Explore-post chat is a
separate per-viewer source that uses only the privacy-filtered public post and
Species Dictionary projection. Neither source receives raw media or exact GPS.

See:

- [`insight-chat` route contract](../../../../../../services/supabase/functions/insight-chat/README.md)
- [Scan ingestion reliability and recovery](../../../../../../docs/backend-and-data/16-scan-ingestion-reliability-and-recovery.md#field-chat-readiness)
- [Insight sheet architecture](../../../../../../docs/features-and-hardware/05-insight-sheet.md)
