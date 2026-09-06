# SOCLab architecture-as-code

GitLab is the source of truth for architecture metadata and review history. Eraser is the collaborative diagram editor.

## Shared Eraser workspace

- File: https://app.eraser.io/workspace/is00JQNKMBOR7VE81O2t
- Runtime architecture: https://app.eraser.io/workspace/is00JQNKMBOR7VE81O2t?diagram=t8gLVUsP-pbVrqQoSTae&layout=canvas
- Installation and verification flow: https://app.eraser.io/workspace/is00JQNKMBOR7VE81O2t?diagram=APJupz-HUPJEYlJabdDZ&layout=canvas

## Versioning contract

Each diagram has a small versioned manifest in this directory. The manifest binds a Git revision to the Eraser file and diagram IDs and records the architectural scope. Editable diagram definitions can be exported/captured here when the Eraser integration supports that workflow. Generated PNG/JPEG previews are review artifacts, not the authoritative source.

Eraser must not contain passwords, tokens, private keys, credential values, or other runtime secrets.

## Change policy

Changes to runtime or integration architecture must update `docs/diagrams/` in the same merge request. The CI architecture-impact job treats changes under `install.sh`, `lib/`, `integrations/`, `detections/`, `docker/`, `.gitlab-ci.yml`, and related runtime configuration as architecture-sensitive.

When a change genuinely has no architecture impact, create or update `docs/diagrams/architecture-no-change.md` in the same merge request with a short justification. This makes the exception explicit and reviewable instead of silently allowing diagram drift.

## Intended lifecycle

1. Change implementation on a GitLab feature branch.
2. Update the relevant diagram in the shared Eraser file.
3. Capture/update the diagram manifest/source in `docs/diagrams/`.
4. CI validates that architecture-sensitive changes include architecture documentation or an explicit no-change decision.
5. Review code and architecture together in the merge request.
6. Merge to `main`; MkDocs/GitLab Pages publishes the documentation.

There is no claim of automatic two-way Eraser/GitLab synchronization. Any future Eraser API/webhook automation should preserve GitLab as the review and version-control boundary.
