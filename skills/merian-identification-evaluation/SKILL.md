---
name: merian-identification-evaluation
description: "Plan, audit, interpret and organize Merian identification experiments across models, prompts, media preparation, taxonomy, answerability and confidence calibration. Use for identification quality comparisons, evaluation datasets, exposure review, task benchmark qualification, model assignment recommendations, research decisions or experiment execution; not ordinary AI UI changes or unrelated unit tests."
---

# Merian identification evaluation

Start with the [research index](../../docs/research/identification/README.md),
then read only the relevant
[experiments](../../docs/research/identification/experiments.md) and
[dataset families](../../docs/research/identification/datasets.md). The
[procedure](../../docs/research/identification/procedure.md) owns the research
workflow. For benchmark qualification or task-to-model recommendations, read the
[capability matrix](../../docs/research/identification/capabilities.md) and
[qualification contract](../../docs/research/identification/benchmark-contract.md).
Existing reports and frozen evidence own historical facts; the skill must not
become another copy of results or operating commands.

## Apply the right evidence boundary

- Before proposing work, identify the unresolved question and the prior result
  that justifies it. Do not repeat a closed study merely to seek a winning
  answer.
- Read the selected runner's section in the
  [evaluator guide](../../services/supabase/scripts/identification_evaluation/README.md).
  Reuse its builders, scoring, accounting, claims and source binding. A catalog
  entry or synthetic pass never authorizes a provider invocation.
- Check actual private input/cluster manifests and attempt history before
  claiming fresh validation data. Historical split names do not prove current
  non-exposure.
- Distinguish biological identification, appropriate rank/abstention, unknown
  mappings, technical failures and confidence calibration. Never infer missing
  names from hashes or turn provider agreement into ground truth.
- Qualify the exact task/configuration/pipeline and benchmark version, not a
  model family. A retained baseline, valid metadata or green software gate is
  not qualification or a product assignment. Preserve unknown legacy identities;
  do not resolve historical studies against today's runtime registry.
- Preserve the original references and accepted-answer sets after collection.
  Record corrections or rescoring as separately versioned evidence.
- Use authorization already granted for the current scope; preserve explicit
  caps and stop rules. Closed budgets remain closed. Hidden credentials stay out
  of source, prompts, logs and evidence. Production operations remain governed
  by `AGENTS.md` and the relevant release runbook.

## Complete the task and leave a usable record

For analysis, report the evidence-supported decision and its limits without
requiring a new experiment. For execution, follow the frozen protocol through
collection, accounting and closure; finish independent offline work if
credentials or another external dependency is unavailable.

For code, also load `$merian-supabase`, `$merian-ios` or `$merian-api-contracts`
when the change enters their scope. Follow the repository's Supabase skill
order. Use `$merian-docs-sync` for ownership or documentation drift. Keep
software validation, model results, deployment and device verification separate.
Do not demand unrelated release gates for a research-only summary.

Update [catalog.json](../../docs/research/identification/catalog.json) with
source links, explicit unknowns, study state and dataset lineage. Update
affected task/configuration assessments in
[capabilities.json](../../docs/research/identification/capabilities.json), and
follow the qualification contract before recording `qualified_in_scope`.
Preserve original reports and private artifacts; do not copy raw outputs into
the catalog. Regenerate the registers and capability matrix and run
`make validate-identification-research` plus changed-Markdown formatting. Skill
changes require `make validate-agent-assets`.

Use the repository's read-only specialist agents only under `AGENTS.md`
delegation conditions; one primary agent owns writes. An independent review is
particularly useful for a changed scoring, exposure, accounting or cross-surface
contract.
