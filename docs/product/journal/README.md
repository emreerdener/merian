# Journal planning workspace

Status: paused by the user on October 27, 2026. Keep the confirmed product
decisions and prototype plan for later review; do not continue Journal or Book
navigation implementation until the user resumes it. This is not a release
claim. The planning synthesis was last consolidated on October 18, 2026.

Journal is a feature within Naturebook, the public product developed in the
Merian repository. This folder gives it a durable planning home within the
larger project. It does not introduce a separate application or repository.

Dedicated Codex chat: **Journal feature planning**, within the Merian project
(`01a15059-bab6-7792-a153-0d97c72718c7`). The chat is the discussion home; these
documents are the durable planning record.

## Start here

| Document                                 | Responsibility                                                                          |
| ---------------------------------------- | --------------------------------------------------------------------------------------- |
| [Feature brief](brief.md)                | Purpose, audience, vocabulary, first-version direction, and feature boundaries          |
| [Decisions](decisions.md)                | Explicit user choices, working design direction, proposals, and superseded ideas        |
| [UX flows](ux-flows.md)                  | Book navigation, Pages/Pins, adding material, canvas editing, and search                |
| [Roadmap and open questions](roadmap.md) | Remaining decisions, engineering qualification, and implementation acceptance scenarios |
| [Prototype plan](prototype-plan.md)      | Proposed prototype scope, stages, walkthroughs, and review criteria                     |

For a quick review, read the brief, then the prototype plan. The decision log
owns confirmed product choices and their history; UX flows apply those choices
to interactions. The roadmap owns unresolved work. Prototype-only proposals
remain in the prototype plan until explicitly accepted into the decision log.

Read the decision record before interpreting any flow as final. A design shown
in a mockup is working direction, not automatic approval of every behavior an
assistant suggested around it. Only explicit user decisions are marked
confirmed. The user authorized creating this planning workspace and a dedicated
Merian chat; that authorization does not request Journal implementation.

## Relationship to the rest of Merian

- [Master product document](../01-master-product-document.md) provides the wider
  product context. Journal's benefits and revenue outcomes remain hypotheses;
  [J-23](decisions.md#confirmed-free-core-and-pro-enhancements--october-18-2026)
  records the approved Free/Pro direction with allowances and pricing open.
- [Insight contract](../../features-and-hardware/05-insight-sheet.md) and the
  [Field Notes owner](../../../apps/ios/Merian/Features/Insights/FieldNotes/README.md)
  govern existing observation notes. Keep Field Notes separate from Journal.
- [Staged capture and Add details](../../features-and-hardware/29-staged-capture-review.md)
  is the related capture surface. The approved initial-details-to-Field-Notes
  planning addition belongs to the separate **Simplify capture tools** chat
  (`01a12c47-6f54-7500-bab9-679c2babf9a0`). This workspace does not take over
  its implementation or report that addition as implemented.
- [Feature modules](../../features-and-hardware/07-feature-modules-and-ui.md),
  [testing strategy](../../development-guides/08-testing-strategy.md), and
  [documentation ownership](../../CONTRIBUTING.md#documentation-ownership)
  remain the integration and verification references.

## Sources and maintenance

This synthesis records the Journal brainstorming conversation and user-supplied
navigation mockups discussed October 16–18, 2026. The
[shared Gemini brainstorming conversation](https://share.gemini.google/8ig7MnZYukXZ)
is supporting context, not implementation authority. Apple Freeform is the
user's interaction reference; that does not require feature parity.

The screenshots remain in the source conversation. They have not been copied
into Git because they include user-supplied observation imagery. Future
checked-in mockups should use synthetic or appropriately approved assets. The UX
document records their structure without depending on temporary attachment
paths.

Update this workspace when decisions change. Preserve the distinction between
confirmed, proposed, and deferred work. When implementation is authorized,
create or update the relevant canonical feature contracts with source and tests
rather than presenting these planning documents as shipped behavior.
