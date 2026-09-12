# AI Governance

AI is a roadmap capability, not an MVP credibility shortcut.

## Maturity ladder

| Level | AI role | Human role | Gate before advancing |
|---|---|---|---|
| L0 — deterministic MVP | No AI in operating path | Human triage/decision | Reliable platform + evidenced canonical scenario |
| L1 — assistive | Retrieve/summarize context | Human decides | Curated knowledge + evaluation set |
| L2 — recommending | Suggest triage/rules/workflows | Human approves each action | Measured quality above threshold |
| L3 — bounded autonomy | Execute pre-approved low-impact actions | Human governs policy and exceptions | Policy enforcement + rollback + audit |
| L4 — governed autonomy | Execute within approved policy | Human governs risk thresholds | Stable safety metrics over time |

## Action classes

| Impact | Examples | Portfolio rule |
|---|---|---|
| Low | Enrichment, tagging, notification, case creation | Earliest autonomy candidate after evaluation |
| Medium | Reversible containment / workflow branch | Requires rollback and stronger approval policy |
| High | Destructive or hard-to-reverse action | Human approval remains mandatory in portfolio scope |

## Required evidence for any AI capability

- Defined evaluation set and acceptance threshold.
- Decision record with inputs, suggestion, confidence and approver where relevant.
- Fallback to human when confidence or policy threshold is not met.
- Rollback path for autonomous actions.
- Trace linked to the same Verify/evidence model as deterministic actions.
- Safety metrics that can pause autonomy when they regress.

## Credibility rule

No AI capability may be labeled **Implemented** until the implementation and measured evaluation evidence are committed or otherwise reproducibly linked from the repository.
