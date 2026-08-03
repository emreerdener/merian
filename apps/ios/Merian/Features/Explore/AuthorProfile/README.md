# Explore Author Profile

The `AuthorProfile` directory contains the navigation, logic, and UI for a
privacy-scoped public Explore author profile.

It shows aggregate scan progress, non-opening achievements, visible Explore
posts, follow state, and eligible Field trip summaries without exposing private
scan evidence. Administratively hidden posts never appear in profile discovery,
previews, or the full library.

The automatically enrolled Backyard Safari Level 1 row follows the existing
profile-visible status contract, so a new or backfilled account can have an
author-profile surface at `0/N` progress. Stopping or resetting the unfinished
outing hides that active status; no scan evidence becomes public.

For a non-self reportable profile, `viewer_can_report` enables the overflow
menu's **Report user** form. The form accepts one of the server-defined reasons
and optional details up to 1,000 characters, displays loading/error/success
state, and calls `/report-user`. Reporting does not automatically block,
unfollow, hide, or navigate away. The endpoint revalidates self-report and
profile visibility; the decoded flag is not the authorization boundary.

The full product, privacy, API, navigation, and verification contract is in
[`docs/features-and-hardware/14-explore-author-profiles.md`](../../../../../../docs/features-and-hardware/14-explore-author-profiles.md).
