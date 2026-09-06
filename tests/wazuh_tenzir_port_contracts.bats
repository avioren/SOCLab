#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  WAZUH="$REPO_ROOT/lib/wazuh.sh"
}

@test "Wazuh agent host port defaults away from Tenzir 1514" {
  run grep -F 'WAZUH_AGENT_PORT="${WAZUH_AGENT_PORT:-15140}"' "$WAZUH"
  [ "$status" -eq 0 ]
}

@test "Wazuh compose patch keeps container 1514 but remaps the host port" {
  run grep -F '{agent_port}:1514' "$WAZUH"
  [ "$status" -eq 0 ]
  run grep -F 'Wazuh still publishes host TCP/1514; this would conflict with Shuffle/Tenzir.' "$WAZUH"
  [ "$status" -eq 0 ]
}
