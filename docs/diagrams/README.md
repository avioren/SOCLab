# SOCLab architecture-as-code

GitLab is the sole source of truth for SOCLab architecture documentation and review history.

## Beautiful Mermaid pipeline

SOCLab stores editable Mermaid sources under `docs/diagrams/src/*.mmd`. The renderer in `scripts/render-diagrams.mjs` processes every source file with the pinned open-source `beautiful-mermaid` package and writes presentation-ready SVG output to `docs/diagrams/generated/` during CI.

The diagram-rendering job is deliberately independent from installation and runtime jobs. A renderer problem cannot deploy, restart, reconfigure, or tear down any SOCLab service.

Run it locally with:

```bash
npm install --ignore-scripts
npm run diagrams:render
```

CI also publishes the generated SVG directory as a job artifact and regenerates the diagrams before MkDocs validation and GitLab Pages publication.

### Current diagram sources

- `soclab-system.mmd` — platform/service architecture.
- `alert-response-flow.mmd` — detection through SOAR enrichment, response, verification, and tuning.
- `install-runtime-flow.mmd` — installer and runtime readiness lifecycle.
- `ci-documentation-flow.mmd` — GitLab validation and architecture-documentation lifecycle.
- `service-port-topology.mmd` — host-facing service/port ownership map.

Add a new flow by committing another `.mmd` file to `docs/diagrams/src/`; the renderer discovers it automatically.

## Versioning contract

Architecture decisions and topology notes are stored directly in `docs/diagrams/` alongside the implementation they describe. Mermaid source is authoritative. Generated SVG is a derived artifact and must never be hand-edited.

No external diagram editor, synchronization service, workspace, webhook, or API integration is required for the rendering path.

## Change policy

Changes to runtime or integration architecture must update `docs/diagrams/` in the same merge request. The CI architecture-impact job treats changes under `install.sh`, `lib/`, `integrations/`, `detections/`, `docker/`, `.gitlab-ci.yml`, and related runtime configuration as architecture-sensitive.

For visual/topology changes, update or add the corresponding `.mmd` source. When a change genuinely has no architecture impact, create or update `docs/diagrams/architecture-no-change.md` in the same merge request with a short justification.

## Intended lifecycle

1. Change implementation on a GitLab feature branch.
2. Update the relevant Mermaid source and/or architecture decision under `docs/diagrams/`.
3. CI validates architecture impact and renders every Mermaid source.
4. Review code, flow source, and rendered SVG artifact together.
5. Merge to `main`; MkDocs/GitLab Pages publishes the regenerated documentation.
