---
description: Use the explicitly authorized Merian release workflow
---

# Supabase deployment compatibility pointer

Use [`$merian-release`](../../../../.agents/skills/merian-release/SKILL.md) only
after an explicit request naming the production operation and target. Then
follow the
[canonical Supabase deployment runbook](../../../../docs/backend-and-data/06-supabase-deployment-runbook.md)
on an immutable source SHA.

This compatibility entry point is not a second deployment procedure. Candidate
validation is read-only evidence and never authorizes production mutation.
