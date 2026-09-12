# Demo Runbook

The interview demo must separate what the repository proves today from the target end-to-end SOC scenario.

## Act 0 — Frame the product

> “SOCLab treats a SOC lab as a product. The repository already proves reproducible deployment, health, integration-contract validation, CI safeguards and recovery. The next milestone is a single fully evidenced security-event journey.”

## Act 1 — Platform proof (safe to demo now)

1. Show `install.sh` lifecycle commands.
2. Show the reusable `verify` / `healthcheck` model.
3. Walk through Wazuh API, port and Shuffle execution-plane contract checks.
4. Show Bats regression tests and secret-safety CI.
5. Show the latest passing pipeline and architecture-change gate.
6. Show the historical Wazuh API issue and how it became a product requirement.

**Landing line:** “Running containers were not enough, so product health became an explicit contract.”

## Act 2 — Canonical SOC scenario (only after FR-01–FR-05 are evidenced)

| Stage | Demo action | Required evidence |
|---|---|---|
| Trigger | Fire committed deterministic event | Test command / fixture |
| Detect | Show expected Wazuh alert | Rule/alert context |
| Route | Show Shuffle invocation | Workflow trace |
| Enrich / decide | Show deterministic workflow output | Workflow run record |
| Respond | Show safe response | Action outcome |
| Verify | Show final evidence | Trace/log/output artifact |

Do not present this act as implemented until [Evidence Matrix](EVIDENCE_MATRIX.md) marks FR-01 through FR-05 as evidenced.

## Act 3 — Useful failure

Once the canonical scenario exists, deliberately break one safe integration boundary and show that diagnosis identifies the failing contract.

Until then, use the historical Wazuh API endpoint/configuration incident as the failure-learning story rather than simulating unsupported automation.

## Fallback

For interviews, keep captured output from a successful local `./install.sh verify` and, once implemented, a captured canonical scenario. A reproducible captured run is a legitimate fallback when the live lab is unavailable.
