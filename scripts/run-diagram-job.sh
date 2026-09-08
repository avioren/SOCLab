#!/usr/bin/env bash
set -euo pipefail

JOB_NAME="generate_diagrams"
PROJECT_ID="86128192"

if ! command -v glab >/dev/null 2>&1; then
  echo "[FAIL] glab is required. Install GitLab CLI first." >&2
  exit 1
fi

if ! glab auth status >/dev/null 2>&1; then
  echo "[FAIL] glab is not authenticated. Run: glab auth login" >&2
  exit 1
fi

branch="${1:-$(git branch --show-current)}"
if [[ -z "$branch" ]]; then
  echo "[FAIL] Could not determine current branch. Pass a branch explicitly." >&2
  echo "Usage: $0 [branch]" >&2
  exit 1
fi

project_path="$(glab repo view --json path_with_namespace -q .path_with_namespace 2>/dev/null || true)"
if [[ -n "$project_path" ]]; then
  project_ref="$project_path"
else
  project_ref="$PROJECT_ID"
fi

echo "[INFO] Project: $project_ref"
echo "[INFO] Branch:  $branch"

pipeline_id="$(glab api "projects/${PROJECT_ID}/pipelines?ref=${branch}&order_by=id&sort=desc&per_page=1" --jq '.[0].id // empty')"

if [[ -z "$pipeline_id" ]]; then
  echo "[INFO] No pipeline found for branch. Creating one..."
  pipeline_id="$(glab api --method POST "projects/${PROJECT_ID}/pipeline" -f "ref=${branch}" --jq '.id')"
fi

if [[ -z "$pipeline_id" ]]; then
  echo "[FAIL] Could not resolve a pipeline for branch $branch" >&2
  exit 1
fi

echo "[INFO] Pipeline: $pipeline_id"

job_id="$(glab api "projects/${PROJECT_ID}/pipelines/${pipeline_id}/jobs?include_retried=true&per_page=100" \
  --jq ".[] | select(.name == \"${JOB_NAME}\") | .id" | head -n1)"

if [[ -z "$job_id" ]]; then
  echo "[FAIL] Manual job '$JOB_NAME' was not found in pipeline $pipeline_id." >&2
  echo "       Confirm the branch contains the generate_diagrams CI job." >&2
  exit 1
fi

job_status="$(glab api "projects/${PROJECT_ID}/jobs/${job_id}" --jq '.status')"
echo "[INFO] Job:      $JOB_NAME ($job_id) status=$job_status"

case "$job_status" in
  manual)
    echo "[INFO] Playing manual job..."
    glab api --method POST "projects/${PROJECT_ID}/jobs/${job_id}/play" >/dev/null
    ;;
  created|pending|running)
    echo "[INFO] Job is already queued/running."
    ;;
  success)
    echo "[INFO] Job already completed successfully."
    ;;
  failed|canceled|skipped)
    echo "[INFO] Retrying job..."
    glab api --method POST "projects/${PROJECT_ID}/jobs/${job_id}/retry" >/dev/null
    ;;
  *)
    echo "[FAIL] Unsupported job status: $job_status" >&2
    exit 1
    ;;
esac

echo "[OK] Diagram job invoked."
echo "     View pipeline: https://gitlab.com/${project_path:-secops-garden-group/Secops.Garden-project_Detection_As_Code}/-/pipelines/${pipeline_id}"
