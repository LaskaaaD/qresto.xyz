# DevOps Audit

## Current Baseline

| Category | Status | Notes |
| --- | --- | --- |
| Dockerfile | Pass | Node image pinned by digest, non-root runtime, healthcheck included |
| Compose security | Pass | App uses read-only filesystem, dropped capabilities, internal networks |
| Secrets | Pass | `.env`, inventories, vault files, uploads, backups, and ACME files are ignored |
| CI | Pass | Tests, audit, syntax checks, Compose validation, Ansible syntax validation, and PR Docker builds |
| CD | Pass | Deploy is manual and environment-scoped |
| Ansible | Pass | Split config, inventory example, collection requirements, SSH/firewall hardening |
| Monitoring | Pass with trade-off | Zabbix Agent2 reads host and Docker metadata without privileged mode |
| Backups | Partial | Local backup script exists; off-site encrypted storage is still recommended |

## Least Privilege Review

- `app`: non-root user, no Linux capabilities, read-only root filesystem, upload volume only.
- Images: Node base image and Compose service images are pinned by digest to reduce unexpected drift.
- `traefik`: no direct Docker socket; reads metadata through `docker-socket-proxy`.
- `mongodb`: private backend network only; not exposed on host ports.
- `zabbix-db`, `zabbix-server`: private monitoring network; server port bound to localhost.
- `zabbix-agent2`: no `privileged`, dropped capabilities, read-only host and Docker socket mounts.
- GitHub Actions: minimal permissions at workflow level; package write only in the build job.

## Remaining Improvements

- Add Trivy or Grype image scanning after build.
- Add branch protection requiring the `validate` job.
- Add integration tests using a temporary MongoDB service.
- Ship encrypted off-site backups, for example S3-compatible storage with lifecycle rules.
- Replace the deploy user's Docker group access with a narrower deployment service if this grows beyond a single VPS.
