# Insight Media

The `Media` directory manages the rich visual assets associated with a scan.

## Purpose
This area drives the interactive image carousel at the top of an Insight sheet. It is responsible for seamlessly combining the user's live capture images, any additional staged media, and reference imagery (like GBIF or Wikipedia photos) into a unified viewing experience.

External reference URLs are normalized through
`ExternalReferenceImagePolicy.allowedURLStrings(from:)` before carousel pages
are built. The current policy silently removes iNaturalist media `605615444`
and preserves the order of all remaining URLs. Captured/staged user media is not
subject to this exact third-party denylist. If no permitted reference image
remains, the carousel keeps its existing non-reference media or empty-state
behavior; it never creates a censored placeholder page for the blocked URL.

Reference images also pass through the shared
`ReferenceImageDeduplicationPolicy` before the Insight page model is exposed.
`InsightSheetViewModel.displayMedia(_:)` excludes every visual identifier owned
by the current scan: image and video paths in `ActiveScanMedia`, persisted or
queued thumbnail paths, and the toolbar cover path. Naturebook URL variants for
the same storage object match even when their scheme, query, or fragment differs;
external URLs retain strict full-URL identity.

Filtering happens before `refUrls`, `totalImages`, inline carousel pages, and
fullscreen gallery items are derived. Consequently, inline and fullscreen
views share the same order and count, and an all-duplicate loaded reference set
becomes `.empty` instead of leaving an empty reference page or page indicator.
The rule is scoped to the exact scan, not the author: Naturebook imagery from
another scan remains eligible, as do unrelated Wikipedia and GBIF images.

Image-load availability is tracked per scan and distinguishes captured user
photos from reference imagery. Failed visual pages are excluded once no usable
user image or video remains, and the existing `Original photo unavailable`
state is appended after every audio, description, reference, and loading page.
This terminal page never enters the fullscreen gallery. When other usable user
visuals remain, the established availability ordering still moves failed images
behind usable visual pages and removes them after a reference renders.

Audio pages expose a filename-scoped playback-control accessibility identifier
only after the source has produced both a valid `AVAudioPlayer` and decoded
spectrogram columns. The seeded queued-audio UI regression writes a real PCM WAV
to Documents, waits for that control before completion, and requires the same
readable control after the completed record replaces the queued presentation.
The outer page identifier alone is not media-readiness evidence because it is
also present while decoding and in the unavailable state.

Video pages track the underlying `AVPlayerItem` status instead of treating a
created player as proof that media is playable. Each active video may carry one
retained image fallback: its stored poster first, otherwise the middle of its
five sampled inference frames. An explicitly empty cloud video URL manifest
demotes stale video records to that single image and repairs cached remote
records. Runtime playback failure performs the same replacement in place with
the original stable page ID, so selection is preserved, video/mute controls are
removed, and tapping opens normal fullscreen image zoom. Sampled frames are
never exposed as a five-page replacement.

Inline and fullscreen video each retain a `MediaPlaybackObservation` for the
mounted playback surface. Replacing or dismissing a player removes KVO,
AVPlayerItem notification, and periodic-time tokens from that exact player;
callbacks carry a generation fence so late events from a prior carousel page
cannot update the current page. Do not register ad hoc AVPlayer observers in a
carousel view.
