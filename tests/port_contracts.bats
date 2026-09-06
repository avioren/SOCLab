#!/usr/bin/env bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  INSTALL="$REPO_ROOT/install.sh"
  COMMON="$REPO_ROOT/lib/common.sh"
  WAZUH="$REPO_ROOT/lib/wazuh.sh"
}

@test "port contract is sourced through install runtime and has no duplicate host protocol tuples" {
  run bash -c 'source "$1"; { soclab_application_port_contract; soclab_swarm_port_contract; } | cut -d"|" -f3,4 | sort | uniq -d' _ "$INSTALL"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "Wazuh API stays on host TCP 55000 with no obsolete recovery port" {
  run grep -F 'Wazuh API|127.0.0.1|55000|tcp|55000' "$COMMON"
  [ "$status" -eq 0 ]
  run grep -F '127.0.0.1:55000:55000' "$WAZUH"
  [ "$status" -eq 0 ]
  run grep -R -E '1[5]500' "$REPO_ROOT" --exclude-dir=.git
  [ "$status" -ne 0 ]
}

@test "port contract reserves all application ports used by Wazuh Shuffle OpenSearch and Tenzir" {
  for needle in \
    'Wazuh syslog|0.0.0.0|514|udp|514' \
    'Shuffle/Tenzir syslog|0.0.0.0|1514|tcp|1514' \
    'Wazuh enrollment|0.0.0.0|1515|tcp|1515' \
    'Wazuh agent events|0.0.0.0|${WAZUH_AGENT_PORT:-15140}|tcp|1514' \
    'Shuffle frontend HTTP|0.0.0.0|${SHUFFLE_FRONTEND_PORT:-3001}|tcp|80' \
    'Shuffle frontend HTTPS|0.0.0.0|${SHUFFLE_HTTPS_PORT:-3443}|tcp|443' \
    'Shuffle backend API|0.0.0.0|${SHUFFLE_BACKEND_PORT:-5001}|tcp|5001' \
    'Shuffle/Tenzir API|0.0.0.0|5160|tcp|5160' \
    'Wazuh dashboard|0.0.0.0|${WAZUH_DASHBOARD_PORT:-8443}|tcp|5601' \
    'Wazuh indexer|0.0.0.0|9200|tcp|9200' \
    'Shuffle OpenSearch|127.0.0.1|${SHUFFLE_OPENSEARCH_PORT:-9201}|tcp|9200' \
    'Wazuh API|127.0.0.1|55000|tcp|55000'; do
    run grep -F "$needle" "$COMMON"
    [ "$status" -eq 0 ]
  done
}

@test "Docker Swarm control and overlay ports are part of the collision contract" {
  run grep -F 'Docker Swarm manager|0.0.0.0|2377|tcp|manager control plane' "$COMMON"
  [ "$status" -eq 0 ]
  run grep -F 'Docker Swarm gossip|0.0.0.0|7946|tcp|node discovery/communication' "$COMMON"
  [ "$status" -eq 0 ]
  run grep -F 'Docker Swarm gossip|0.0.0.0|7946|udp|node discovery/communication' "$COMMON"
  [ "$status" -eq 0 ]
  run grep -F 'Docker Swarm VXLAN|0.0.0.0|4789|udp|overlay data plane' "$COMMON"
  [ "$status" -eq 0 ]
}

@test "clean install performs real Docker Desktop port probes before cloning Wazuh" {
  run awk '/^configure_host\(\)/,/^}/ {print}' "$COMMON"
  [ "$status" -eq 0 ]
  [[ "$output" == *'preflight_soclab_ports'* ]]
  run grep -F 'docker run -d --rm --name "$name"' "$COMMON"
  [ "$status" -eq 0 ]
  run grep -F 'probe_soclab_swarm_ports' "$COMMON"
  [ "$status" -eq 0 ]
}

@test "Wazuh compose keeps Tenzir 1514 free while preserving enrollment syslog and API ports" {
  run grep -F 'Wazuh still publishes host TCP/1514; this would conflict with Shuffle/Tenzir.' "$WAZUH"
  [ "$status" -eq 0 ]
  run grep -F '1515:1515' "$WAZUH"
  [ "$status" -eq 0 ]
  run grep -F '514:514/udp' "$WAZUH"
  [ "$status" -eq 0 ]
  run grep -F 'host TCP/55000 -> container TCP/55000' "$WAZUH"
  [ "$status" -eq 0 ]
}
