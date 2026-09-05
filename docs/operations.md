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
8. Stored Wazuh indexer/admin and Wazuh API credentials authenticate when the local credential file is readable.
9. Shuffle OpenSearch credential authentication is checked when its endpoint is directly reachable.
10. Shuffle frontend responds over HTTP or HTTPS.

A non-zero exit code means at least one required health gate failed.

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

## Credentials inventory

```bash
./install.sh credentials
```

This command shows the location and permissions of the local credential inventory but does not print the secret values. To display the file, do so explicitly on the lab host:

```bash
cat /opt/soclab/state/credentials.txt
```

The reusable healthcheck uses this file, when readable, to verify Wazuh indexer/admin and Wazuh API authentication. Secret values are never included in the healthcheck table or logs.
