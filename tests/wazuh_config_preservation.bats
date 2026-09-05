#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  FIX="$REPO_ROOT/lib/wazuh_config_preserve.sh"
  SHUFFLE="$REPO_ROOT/lib/shuffle.sh"
}

@test "Wazuh certificate regeneration preserves component config directories" {
  run grep -F 'rm -rf "$ca_dir"' "$FIX"
  [ "$status" -eq 0 ]

  run grep -F 'rm -rf "$idx_dir"' "$FIX"
  [ "$status" -ne 0 ]

  run grep -F 'rm -rf "$mgr_dir"' "$FIX"
  [ "$status" -ne 0 ]

  run grep -F 'rm -rf "$dash_dir"' "$FIX"
  [ "$status" -ne 0 ]
}

@test "Wazuh beta5 internal_users.yml must exist before and after TLS generation" {
  run grep -F 'Expected beta5 config file missing before certificate generation: $idx_dir/internal_users.yml' "$FIX"
  [ "$status" -eq 0 ]

  run grep -F 'Certificate generation deleted internal_users.yml' "$FIX"
  [ "$status" -eq 0 ]
}

@test "Wazuh indexer and dashboard config files are preserved" {
  run grep -F '$idx_dir/wazuh.indexer.yml' "$FIX"
  [ "$status" -eq 0 ]

  run grep -F '$dash_dir/wazuh.yml' "$FIX"
  [ "$status" -eq 0 ]
}

@test "config preservation override loads after wazuh module" {
  run grep -F 'source "$SCRIPT_DIR/lib/wazuh_config_preserve.sh"' "$SHUFFLE"
  [ "$status" -eq 0 ]
}
