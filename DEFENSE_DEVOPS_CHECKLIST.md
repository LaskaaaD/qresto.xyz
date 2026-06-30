# DevOps Defense Checklist

Use this file to explain the project in an interview or course defense.

## What This Project Demonstrates

- A working Node.js application packaged as a production Docker image.
- A Compose stack with reverse proxy, TLS, application, database, and monitoring.
- VPS provisioning with Ansible.
- CI validation and dependency auditing.
- GHCR image publishing and manual production deployment.
- Monitoring and maintenance tasks through Zabbix and cron scripts.

## Security Decisions

| Area | Decision |
| --- | --- |
| Application image | Runs as the `node` user, not root |
| Image supply chain | Dockerfile base image and Compose service images are pinned by digest |
| Filesystem | Application container uses `read_only: true` and a named upload volume |
| Linux capabilities | Application and proxy containers drop all capabilities |
| Docker socket | Traefik uses a read-only socket proxy instead of a direct socket mount |
| Networks | Backend and monitoring networks are internal |
| CI/CD permissions | Workflow-level `contents: read`; package write only in the build job |
| PR validation | Pull requests run tests, audits, Compose validation, Ansible syntax validation, and Docker image build |
| Deploy trigger | Production deploy is manual and should be protected by a GitHub environment |
| Secrets | Real secrets live in GitHub Actions and `/opt/qresto/.env`, never in Git |
| SSH | Password login and root login are disabled by Ansible |
| Firewall | UFW exposes only SSH, HTTP, and HTTPS |

## Known Trade-Offs

- The deploy user belongs to the `docker` group. This is common for small VPS deployments, but it is a high-trust permission.
- Zabbix Agent2 reads host and Docker metadata. It is not privileged and uses read-only mounts, but it still has broader visibility than a pure application container.
- The included app tests are intentionally small. For a real SaaS project, route, auth, upload, and database integration tests should be expanded.
- Backups are local by default. Production should add off-site encrypted backups.

## Interview Talking Points

- Why deploy is manual instead of automatic from every push.
- Why action versions are pinned by SHA.
- Why `docker.sock` is proxied for Traefik.
- Why `.env.example` contains placeholders and `.env` is ignored.
- What `read_only`, `cap_drop`, `no-new-privileges`, and internal networks protect against.
- What should be improved next: stronger tests, external backup storage, vulnerability scanning with Trivy, and GitHub branch protection.
