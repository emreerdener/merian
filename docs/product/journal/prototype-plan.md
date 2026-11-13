# Journal prototype plan

Status: paused by the user on October 27, 2026. Retain this proposed approach
from October 18 for later review. This document plans a prototype; no
interactive prototype has been built as part of this planning cleanup. Confirmed
product requirements remain in the [decision log](decisions.md).

## Goal

Test whether someone can save the media they intend, place it on a page, and
understand how to select, arrange, play, reuse, and remove it without losing
their work or confusing a page copy with a Pin.

Start with one complete journey:

```text
View source media -> Add to journal -> select media -> Add to page
  -> New page / recent page / search pages -> confirmation with View
  -> open page -> select and arrange an item -> Show details
  -> return to Pins -> reuse a Pin -> edit/remove one independent copy
```

Include Save to Pins as the alternate destination and insertion from an open
page as the route that skips destination selection. Keep the current-item,
no-current-item, and sole-item defaults from J-30.

## Recommended format and boundaries

Build a local interactive browser prototype at an iPhone-sized viewport first.
It should be touch-usable on a phone and reviewable on desktop. This lets us
iterate on navigation, selection, menus, and composition before choosing native
storage or canvas architecture. Use a small self-contained implementation with
bundled synthetic or approved assets and deterministic fixtures. Keep it outside
shipping application modules, with launch/reset instructions when built.

Use a small in-memory model for sources, reusable Pins, pages, and independent
placements. This is enough to make selection, placement, Undo, and copy behavior
real within a session. It is a prototype model, not a production schema. Reload
may reset the fixture; make that limitation clear in the review instructions. No
account connection, real scan data, network sync, external media lookup,
billing, or publication is needed.

Use a later focused SwiftUI/device experiment for questions the browser cannot
answer reliably: one-finger drawing versus two-finger navigation, sheet and
keyboard behavior, media-player interaction, VoiceOver, large text, memory, and
large-canvas performance. Browser success does not establish native feasibility.

## Visual reference

Use the user's updated five-screen board as the visual baseline: dark rounded
Book surfaces, Pages/Pins navigation, Pages gallery, media-category Pins rows,
expanded Photos search, dotted canvas, translucent controls, and blue actions.
Gallery filter semantics remain open even though their controls appear in the
reference.

The generated media-picker/selected-photo board and photo/video/audio selection
board are static studies. Carry forward the requested common-name species tag,
visible menu button, selection handles, and appropriate playback controls. Test
the precise geometry and hit targets rather than treating generated pixels or
incidental menu entries as approved design.

Keep observation screenshots in the conversation. Use synthetic or explicitly
approved media in any durable prototype artifact. Use the existing Explore
species-tag treatment as the visual reference and inspect the existing audio
spectrograph/waveform owner before attempting production reuse. Authored canvas
notes in the reference do not authorize Field Notes import.

## Build in three reviewable passes

### Pass 1: source to selected canvas item

Create one shared flow with personal-scan, Explore, and Species Dictionary
fixture entry points. They should vary source context and available media while
using the same picker/destination logic.

Implement within-session selection, count/disabled states, cancellation,
destination choice, creation of a page, confirmation with View, and independent
placements. Include a selected photo, paused video, and playable synthetic audio
sample with a spectrograph/waveform visual. Selection must not start playback;
preview/play must not toggle picker selection. Show metadata through the visible
object menu and hide the common-name tag when deselected.

Two open questions need concrete alternatives at this pass:

- **Page naming:** compare a name field during New page with creating an
  untitled page that can be named from the editor. Test empty/cancel behavior;
  neither option is a confirmed requirement.
- **Multiple-item placement:** begin with slightly offset, independent items
  placed visibly in the current viewport. Compare a loose spread if overlap
  hides useful content. This is a proposed layout, not a new grouping or
  multi-item Pin contract.

Keep nonessential gallery filters inactive or explicitly marked as outside the
walkthrough. Do not invent Favorites behavior to make the mockup look complete.

### Pass 2: composition and reuse

Add actual session-level move/resize/rotate, pan/zoom, Fit all, text editing,
simple ink, shared Undo/Redo, and a Pins gallery that reuses the same saved Pin
as independent placements. Provide non-gesture controls for basic manipulation
and keyboard-accessible menus in the browser.

Represent the approved drawing tool set, but label any simplified brush/eraser
behavior in review notes. Browser ink is an interaction study, not validation of
the native drawing engine. Test small and rotated objects, overlapping media,
the visible menu entry point, and controls that remain usable during playback.

Include Remove from page and Delete from Pins with the J-13 distinction and
Undo. Page rename/duplicate/delete/recovery can use reviewable state screens
until their behavior is decided; do not infer page-deletion policy from Pin
deletion. Add local fixture search with query preservation, close-to-clear, and
navigation to the matching page object. Preview Image/PDF framing, credits, and
static audio/video rendering without promising generated production exports.

### Pass 3: recovery and review

Use a reviewer-only scenario switcher, outside product navigation, to show
offline/synced/unsynced, undownloaded audio/video, unavailable media,
conflicting edits, sign-out warning, and storage-limit states. Also show
own-scan deletion, Explore withdrawal with attributed fallback or placeholder,
and deliberate snapshot-update preview. Preserve the confirmed policies; present
unresolved choices as alternatives for review.

These are deterministic simulations. They test whether users understand the
message and available actions; they do not prove durability, permissions,
conflict merging, erasure, source matching, or storage accounting. Do not choose
prices or allowances. The [roadmap](roadmap.md) owns that qualification work.

## What works versus what is simulated

| Interactive within the session                                                 | Simulated or preview-only                                                  | Later native/engineering proof                                             |
| ------------------------------------------------------------------------------ | -------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| Picker, destinations, confirmation, pages/Pins and independent copies          | Account identity, saved/synced status, conflicts, sign-out, storage limits | Durable local saving, migrations, account isolation, sync and recovery     |
| Object selection/manipulation, basic ink/text, Undo/Redo, local fixture search | Page lifecycle options not yet decided; simplified brush rendering         | Native gestures, drawing fidelity, accessibility, indexing/performance     |
| Bundled audio/video playback with explicit controls                            | Downloads, withdrawn sources, fallback lookup, source-version updates      | Real media ownership, permissions, retention, withdrawal propagation       |
| Export framing and composition preview                                         | Image/PDF settings and share completion                                    | Output generation, metadata exclusion, sizing, permissions, system sharing |

## Walkthrough and review criteria

Run these tasks on a phone-sized view, then repeat critical selection/playback
and manipulation tasks on a touch device. Observe without coaching where
possible; record the screen/state, expected behavior, observed problem, and
proposed change. This is a design review, not a request to add analytics.

| Task                                                              | Evidence to look for                                                                                                            |
| ----------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Add the photo currently being viewed                              | Correct preselection; user can change it; no whole-source or Field Notes import                                                 |
| Enter without a current item, then with a sole item               | Empty versus sole-item defaults are understandable; zero selection cannot save; Cancel has no effects                           |
| Preview audio/video in the picker                                 | Playback and selection remain separate; count stays correct                                                                     |
| Add selected media to a new/recent/searched page, or save to Pins | Only chosen media is saved; destination is understandable; confirmation stays on source until View                              |
| Insert source media while already on a page                       | No redundant destination step; applicable J-13 save rules are preserved                                                         |
| Select, arrange, and inspect each media type                      | Tag/menu/handles do not collide; selection does not play; Show details is discoverable; missing-name variant is reviewed        |
| Reuse a Pin, edit one placement, delete the Pin                   | Other placements remain unchanged; source/credit survive; removal semantics and Undo are understood                             |
| Add text/ink, Undo/Redo, and Fit all                              | Arrange/Draw modes are clear; content stays in canvas coordinates; basic actions have accessible alternatives                   |
| Search, open a result, go Back, then close                        | Matching object is reachable; query persists within search and clears on close                                                  |
| Preview an export and unavailable media                           | Selection/playback UI and hidden metadata are excluded; credits remain; visible composition and missing-media choices are clear |
| Review recovery/source-change scenarios                           | Local versus synced state is understood; conflicting work is preserved; withdrawal is not undone by snapshot/conflict recovery  |

Complete this prototype review when the core journey can be walked through
without explaining hidden controls, critical ambiguities have a resolved design
or a named next experiment, and all departures from J-01–J-30 have been accepted
or removed. Keep remaining native/engineering questions in the roadmap.

## Handoff

Deliver the runnable local prototype, fixture/reset instructions, a compact
screen/state inventory, and review findings tied to the walkthrough above.
Record accepted decisions in the decision log and update the brief/flows only
where those decisions change them. Retain prototype limitations alongside the
artifact so a polished mockup is not mistaken for production behavior.

The next design action is Pass 1: media selection through a selected canvas
item, including the two page-naming/placement alternatives. Native experiments
and application implementation follow their own scoped plans after review.
