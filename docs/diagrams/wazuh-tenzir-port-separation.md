# Wazuh / Tenzir host-port separation

Status: **adopted for the single-host SOCLab**

Both Wazuh agent traffic and Shuffle's built-in Tenzir/Sigma runtime use TCP/1514 by default. They cannot both publish the same host port on one Docker Desktop daemon.

SOCLab therefore keeps each product's container-internal protocol unchanged and separates only the host mapping:

```text
Windows / external Wazuh agent
        |
        | TCP/15140 on Docker host
        v
Wazuh manager container TCP/1514

Syslog / Sigma test traffic
        |
        | TCP/1514 on Docker host
        v
Shuffle Tenzir runtime TCP/1514
```

Installer invariant:

- `WAZUH_AGENT_PORT` defaults to `15140` and maps host `${WAZUH_AGENT_PORT}` to Wazuh manager container `1514/tcp`.
- The installer must fail if the Wazuh Compose file still publishes host `1514:1514` after patching.
- Tenzir remains enabled and retains host TCP/1514.
- Wazuh internal service configuration remains on TCP/1514; only the Docker host publication changes.

This is required specifically because Wazuh and Shuffle/Tenzir share one Docker Desktop daemon in the interview lab.
