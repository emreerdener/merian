# User Profile

The `UserProfile` directory contains the user-facing screens and components that
make up the main profile tab.

## Structure

- **Views**: Contains the primary view for this area, `ProfileTabView.swift`.
- **Components**: Contains reusable UI elements specific to the profile view,
  such as stats displays, achievement cards, heatmap graphs, and the recent scan
  grid.
- **Models**: Defines the data structures and domain logic exclusively needed
  for rendering the user's profile and gamification stats.
- **Utilities**: Helper functions and extensions tailored to profile data
  manipulation.

## Purpose

This product area is responsible for displaying the user's identity and
progress. It presents the running species count, scan streaks, the 52-week
rolling contribution heatmap, achievements, and user collections. It consumes
state from the shared `ProfileViewModel`.

## Presentation and avatar lifecycle

`ProfileTabView` owns one typed `ProfileTabPresentation` slot for paywall,
Insight, and Field-trip author sheets. `AchievementDetailSheet` likewise uses
one `AchievementDetailPresentation` value for Insight and author detail. New
modal destinations must join the owning enum instead of adding a sibling
`.sheet`.

`UserProfile` serializes username, display-name, and avatar-crop destinations
through one local presentation value and refuses to open an editor while the
system Photos picker owns the presentation slot. Avatar selection and upload
work is stored, cancellable, account-fenced, and request-fenced. A prepared
image may mount the cropper only when its request remains current and the slot
is empty. If preparation wins before the Photos picker dismisses, one bounded
preview waits for the binding to close instead of mounting over the picker or
being dropped. Late work from a replaced selection or account must not mutate
UI. Opening a replacement picker/editor, changing accounts, or leaving the view
cancels selection work and clears its staged preview. Upload preparation is
serialized and verifies the captured account again after each suspension. Avatar
errors remain pending until the picker and typed presentation slot are both
clear; account replacement clears them so stale failures cannot appear in
another user's profile.
