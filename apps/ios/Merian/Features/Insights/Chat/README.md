# Insight Chat

The `Chat` directory contains the logic and UI for the Pro-tier Field Chat feature.

## Purpose
This area allows Pro users to ask contextual follow-up questions about a completed biological scan without needing to re-upload raw images. It also provides the shared presentation and floating control used by private per-viewer chats on every visible Explore post, including the viewer's own posts. Insight conversations use owner-only scan context; Explore conversations use only the privacy-filtered public post and Species Dictionary projection. Both use Gemini 2.5 Flash and smart prompt chips.

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
shown to other viewers. Technical context limitations remain
enforced by the backend and documented in the API contract instead of being
presented as additional empty-state disclaimers.
