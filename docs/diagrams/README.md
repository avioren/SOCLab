# SOCLab architecture-as-code

GitLab is the sole source of truth for SOCLab architecture documentation and review history.

## Versioning contract

Architecture decisions and topology notes are stored directly in `docs/diagrams/` as versioned Markdown alongside the implementation they describe. No external diagram editor, synchronization service, manifest, workspace, webhook, or API integration is required.

Generated PNG/JPEG previews may be used as review artifacts, but the authoritative architecture record is the content committed to GitLab.

## Change policy

Changes to runtime or integration architecture must update `docs/diagrams/` in the same merge request. The CI architecture-impact job treats changes under `install.sh`, `lib/`, `integrations/`, `detections/`, `docker/`, `.gitlab-ci.yml`, and related runtime configuration as architecture-sensitive.

When a change genuinely has no architecture impact, create or update `docs/diagrams/architecture-no-change.md` in the same merge request with a short justification. This keeps the exception explicit and reviewable.

## Intended lifecycle

1. Change implementation on a GitLab feature branch.
2. Update the relevant architecture decision or topology note in `docs/diagrams/`.
3. CI validates that architecture-sensitive changes include architecture documentation or an explicit no-change decision.
4. Review code and architecture together in the merge request.
5. Merge to `main`; MkDocs/GitLab Pages publishes the documentation.

SOCLab has no dependency on an external diagram service.
