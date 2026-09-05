#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "GitLab CI exists" {
  [ -f "$REPO_ROOT/.gitlab-ci.yml" ]
}

@test "documentation config exists" {
  [ -f "$REPO_ROOT/mkdocs.yml" ]
  [ -f "$REPO_ROOT/docs/index.md" ]
}

@test "credentials and runtime state are ignored" {
  run grep -F 'credentials.txt' "$REPO_ROOT/.gitignore"
  [ "$status" -eq 0 ]
  run grep -F '.env' "$REPO_ROOT/.gitignore"
  [ "$status" -eq 0 ]
}
