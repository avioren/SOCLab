# SOCLab architecture and product diagrams as code

GitLab is the sole source of truth for SOCLab diagram source, architecture documentation, and review history.

## Beautiful Mermaid pipeline

Editable Mermaid sources live under `docs/diagrams/src/*.mmd`. The renderer in `scripts/render-diagrams.mjs` processes every source file with the pinned open-source `beautiful-mermaid` package and writes presentation-ready SVG output to `docs/diagrams/generated/` during CI.

The diagram job is independent from installation and runtime jobs. A renderer problem cannot deploy, restart, reconfigure, or tear down a SOCLab service.

Run the renderer locally with:

```bash
npm install --ignore-scripts
npm run diagrams:render
```

CI publishes the generated SVG directory as a job artifact and regenerates diagrams before MkDocs validation and GitLab Pages publication.

## Product-story sources

- `product-story.mmd` — users, friction, product response, evidence, and intended outcome.
- `analyst-journey.mmd` — the signal-to-action journey with an explicit distinction between implemented runtime evidence and the still-unproven end-to-end SOC scenario.
- `product-evolution.mmd` — product progression from reliability through evidence, observability, AI assistance, and governed autonomy.

The GitHub-facing narrative is in `docs/product-story.md`, where the same product concepts are presented as GitHub-native Mermaid diagrams.

## Versioning contract

Architecture decisions and topology notes remain versioned directly in `docs/diagrams/` alongside the implementation they describe. Mermaid source is authoritative for rendered visual assets; generated SVG is derived output and must never be hand-edited.

No external diagram editor, synchronization service, workspace, webhook, or API integration is required for the rendering path.

## Change policy

Changes to runtime or integration architecture must update `docs/diagrams/` in the same merge request. The CI architecture-impact job treats changes under `install.sh`, `lib/`, `integrations/`, `detections/`, `docker/`, `.gitlab-ci.yml`, and related runtime configuration as architecture-sensitive.

For visual or topology changes, update or add the corresponding `.mmd` source. When a change genuinely has no architecture impact, create or update `docs/diagrams/architecture-no-change.md` in the same merge request with a short justification.

## Intended lifecycle

1. Change implementation or product evidence on a GitLab feature branch.
2. Update the relevant Mermaid source and/or architecture decision under `docs/diagrams/`.
3. CI validates architecture impact and renders every Mermaid source.
4. Review implementation, narrative, flow source, and rendered SVG artifact together.
5. Merge to `main`; MkDocs/GitLab Pages publishes the documentation and the repository mirror exposes the same source on GitHub.
