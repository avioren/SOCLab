# Troubleshooting

## Indexer cannot read `root-ca.pem`

The beta5 images use service UID/GID `101:101` in the environment where this installer was validated. The installer does **not** hard-code that value: it detects the UID/GID from each pulled beta5 image and sets private-key ownership accordingly. It then runs a certificate readability preflight inside each service image before Wazuh starts.

## Dashboard returns HTTP 401

HTTP `401` or `403` from the dashboard `/login` endpoint still proves the HTTPS service is alive. The reusable healthcheck treats these responses as valid liveness.

## Container name differs

Health checks use Compose service IDs (`docker compose ps -q --all <service>`), not hard-coded names such as `single-node-wazuh.manager` or a `-1` suffix.

## Collect logs

```bash
./install.sh status
./install.sh healthcheck
./install.sh logs wazuh
```
