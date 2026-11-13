# Naturebook workspace destinations

These are project routing identifiers, not credentials or authorization. Verify
them with the connected tools; do not infer access from a stored identifier.
Verified October 31, 2026 after reconnecting from the personal workspace.

| Resource            | Verified destination                                                                  |
| ------------------- | ------------------------------------------------------------------------------------- |
| Workspace           | Naturebook; `bb0bf299-f780-8189-a892-0003aafd9c22`                                    |
| Home                | [Naturebook](https://app.notion.com/p/4c2bf299f78083bcb54f8116296adcc5)               |
| Engineering         | [Engineering](https://app.notion.com/p/f2dbf299f78083b4bfd581296672c5ca)              |
| Skills directory    | [Skills & Agent Workflows](https://app.notion.com/p/40abf299f78081b0b3caff9b72e124da) |
| Working guide       | [Planning & Operations](https://app.notion.com/p/821bf299f78083408f3681c36fe4cb80)    |
| Delivery database   | [Delivery](https://app.notion.com/p/222bf299f780824b813a812933a61a82)                 |
| Delivery collection | `collection://6bcbf299-f780-8221-8476-07c564880314`                                   |
| Decision database   | [Decisions & Issues](https://app.notion.com/p/cdbbf299f7808346a596814df682854e)       |
| Decision collection | `collection://900bf299-f780-8207-9e72-0732a870694c`                                   |

Fetch current schemas and views rather than treating this reference as a copy of
their properties. Titles can change; the workspace ID and ancestry establish the
intended destination. If an ID becomes unavailable, search only the verified
Naturebook workspace, compare ancestry and confirm identity before updating the
reference. Never fall back to an identically named personal-workspace copy.

## Authority and current planning boundaries

- Root `AGENTS.md` owns universal repository rules. The skills directory links
  canonical instructions under `skills/`; `.agents/skills/` discovers them.
  Plugin-provided general Notion skills and Notion-enabled workspace skills are
  distinct from this directory. Do not copy them into the application
  repository.
- The approved home and working guide own Notion organization. Search for and
  read a workspace Agent Operating Guide if one has since been established. Do
  not automatically import the personal workspace's guide or memory database.
- At setup, substantial infrastructure was explicitly unreleased, the founder
  operating plan was pending review, and Journal was paused. Recheck current
  decisions before planning; these dated facts are not permanent feature policy.
- Store approvals with their provenance, not the date a page was imported or
  modified. Keep current requirements, implemented source and release evidence
  separate; discrepancies need an explicit record rather than silent overwrite.

## Skill directory maintenance

The Notion directory is a concise catalog: skill name, purpose, trigger, source,
review date and availability. Existing skill source links may follow `main` for
navigation; new local skills must be labeled unpublished until their source is
actually accessible. Never claim a skill is remotely published or enabled merely
because its row exists. If Notion is unavailable, report the pending catalog
update and keep the repository's required documentation accurate.
