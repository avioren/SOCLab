# SOCLab architecture-as-code

GitLab is the sole source of truth for SOCLab architecture documentation and review history.

## Versioning contract

Architecture decisions and topology notes are stored directly in `docs/diagrams/` as versioned Markdown alongside the implementation they describe. Mermaid source files live under `docs/diagrams/source/`; publication-ready SVGs are written to `docs/diagrams/generated/`.

Diagram generation is intentionally separate from SOCLab installation and runtime verification. `install.sh`, `verify`, and `healthcheck` never generate diagrams.

## Invoke diagram generation

SOCLab uses Beautiful Mermaid `1.1.3` inside a repository-owned Docker image. Node.js/npm do not need to be installed on the lab host.

Local render:

```bash
./scripts/generate-diagrams.sh
```

Validate all diagram sources without changing generated files:

```bash
./scripts/generate-diagrams.sh --check
```

GitLab also exposes a separate manual `generate_diagrams` CI job. Start it only when SVG artifacts are wanted; it is not part of normal CI execution.

The only host requirements for local generation are Bash and a reachable Docker daemon. The renderer image is built automatically from the pinned repository Dockerfile.

## Change policy

Changes to runtime or integration architecture must update `docs/diagrams/` in the same merge request. The CI architecture-impact job treats changes under `install.sh`, `lib/`, `integrations/`, `detections/`, `docker/`, `.gitlab-ci.yml`, and related runtime configuration as architecture-sensitive.

When a change genuinely has no architecture impact, create or update `docs/diagrams/architecture-no-change.md` in the same merge request with a short justification.

## Intended lifecycle

1. Change implementation on a GitLab feature branch.
2. Update the relevant architecture source or topology note.
3. CI validates architecture-sensitive changes.
4. Optionally invoke the standalone diagram generator locally or through the manual GitLab job.
5. Review code and architecture together.
6. Merge to `main`; MkDocs/GitLab Pages publishes the documentation.
