# Security Policy

## Public repository model

This project publishes source code only. Public read access to the repository does not expose, host, or grant access to a deployed SOC lab.

GitLab Pages, CI job logs and artifacts, environments, infrastructure, packages, container images, and security reports remain restricted to project members.

## Required deployment boundary

The following management/data-plane services should be reachable only from the local host or a trusted administrative network:

- Wazuh Dashboard
- Wazuh Indexer / OpenSearch
- Wazuh API
- Shuffle backend API
- Shuffle OpenSearch
- Tenzir management API
- Docker Engine / Docker Swarm control plane

Agent enrollment, agent event ingestion, and intentionally configured syslog listeners are the only services that should be exposed beyond the administrative boundary, and only when host/firewall policy requires them.

## Credentials

Never commit runtime credentials, API keys, access tokens, private keys, generated certificates, `.env` files, or `/opt/soclab/state/credentials.txt`.

The lab currently relies on some pinned upstream Wazuh beta defaults internally. Do not expose services protected by stock/default credentials to untrusted networks. Rotate or replace default credentials before any non-isolated deployment.

## CI/CD trust boundary

Fork-controlled code must not execute in the parent project CI context. The GitLab project setting blocks parent-project pipelines for fork merge requests; the root `.gitlab-ci.yml` also denies them as defense in depth.

CI/CD job-token access is limited to this project and its explicit allowlist. Job-token repository push remains disabled. Any CI/CD variables containing credentials must be masked, protected, hidden where supported, and scoped as narrowly as possible.

The pipeline runs both a repository-specific, log-redacting credential check and GitLab's maintained secret-detection analyzer.

## Branch protection

The default branch must remain protected. Direct push and merge permissions remain limited to trusted maintainers/owners. Public users may read and fork the project but do not receive write permissions.

## Reporting a vulnerability

Do not publish working credentials, tokens, private keys, or exploit details in a public issue. Use GitLab's private vulnerability-reporting mechanism or contact the project owner privately.
