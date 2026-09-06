#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  COMMON="$REPO_ROOT/lib/common.sh"
}

@test "clean teardown explicitly owns the standalone Tenzir runtime" {
  run grep -F 'remove_tenzir_runtime()' "$COMMON"
  [ "$status" -eq 0 ]
  run grep -F 'docker rm -f -v tenzir-node' "$COMMON"
  [ "$status" -eq 0 ]
  run grep -F 'docker network rm tenzir-network' "$COMMON"
  [ "$status" -eq 0 ]
}

@test "clean_lab invokes Tenzir cleanup before leaving the old Swarm" {
  block="$(awk '/^clean_lab\(\)/,/^}/ {print}' "$COMMON")"
  [[ "$block" == *'remove_tenzir_runtime'* ]]
  [[ "$block" == *'leave_dedicated_single_node_swarm'* ]]

  tenzir_line="$(printf '%s\n' "$block" | grep -n -m1 'remove_tenzir_runtime' | cut -d: -f1)"
  leave_line="$(printf '%s\n' "$block" | grep -n -m1 'leave_dedicated_single_node_swarm' | cut -d: -f1)"
  [ "$tenzir_line" -lt "$leave_line" ]
}

@test "clean teardown asserts no Tenzir residuals remain" {
  run grep -F 'Residual Tenzir container remains after cleanup.' "$COMMON"
  [ "$status" -eq 0 ]
  run grep -F 'Residual Tenzir network remains after cleanup.' "$COMMON"
  [ "$status" -eq 0 ]
}
