# Operations and Healthcheck

## Healthcheck

```bash
./install.sh healthcheck
```

The command verifies:

1. Wazuh indexer container state and Docker health.
2. Wazuh manager container state and Docker health.
3. Wazuh dashboard container state and Docker health.
4. OpenSearch Security health endpoint returns `UP`.
5. Wazuh dashboard HTTPS listener responds. `401`/`403` are valid liveness responses because authentication may be required.
6. Wazuh indexer HTTPS listener responds.
7. Wazuh API HTTPS listener responds.
8. Shuffle frontend responds over HTTP or HTTPS.

A non-zero exit code means at least one health gate failed.

## Status

```bash
./install.sh status
```

## Logs

```bash
./install.sh logs all
./install.sh logs wazuh
./install.sh logs shuffle
```

## Reset

```bash
sudo ./install.sh reset
```

Reset removes only the SOC-lab-owned Compose projects and `/opt/soclab`/`/opt/soar-lab` state.
