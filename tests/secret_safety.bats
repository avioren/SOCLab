#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "repository secret safety scan passes" {
  run "$REPO_ROOT/scripts/check-secrets.sh" "$REPO_ROOT"
  [ "$status" -eq 0 ]
}

@test "repository does not publish the obsolete Wazuh 4.x Docker default" {
  run grep -R -F 'SecretPassword' "$REPO_ROOT/install.sh" "$REPO_ROOT/lib"
  [ "$status" -ne 0 ]
}

@test "generated Shuffle secrets are written by variable reference only" {
  run grep -F 'SHUFFLE_UI_PASSWORD=${shuffle_pw}' "$REPO_ROOT/lib/shuffle.sh"
  [ "$status" -eq 0 ]
  run grep -F 'SHUFFLE_API_KEY=${api_key}' "$REPO_ROOT/lib/shuffle.sh"
  [ "$status" -eq 0 ]
  run grep -F 'SHUFFLE_OPENSEARCH_PASSWORD=${shuffle_pw}' "$REPO_ROOT/lib/shuffle.sh"
  [ "$status" -eq 0 ]
}
