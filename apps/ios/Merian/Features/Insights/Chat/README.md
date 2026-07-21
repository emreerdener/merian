# Insight Chat

The `Chat` directory contains the logic and UI for the Pro-tier Field Chat feature.

## Purpose
This area allows Pro users to ask contextual follow-up questions about a completed biological scan without needing to re-upload raw images. It also provides the shared presentation and floating control used by private per-viewer chats on other users' Explore posts. Insight conversations use owner-only scan context; Explore conversations use only the privacy-filtered public post and Species Dictionary projection. Both use Gemini 2.5 Flash and smart prompt chips.

For Explore posts, the empty state uses the concise trust message
`This Field chat is private and visible only to you.` The conversation is never
shown to the post author or other viewers. Technical context limitations remain
enforced by the backend and documented in the API contract instead of being
presented as additional empty-state disclaimers.
