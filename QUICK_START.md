# Quick Start

This guide takes QResto from a fresh Ubuntu VPS to a manually deployed production stack.

## Requirements

- Ubuntu 22.04+ VPS with initial SSH access.
- A domain managed in Cloudflare.
- Docker Desktop or Docker Engine for local validation.
- Ansible on your workstation.
- GitHub repository with Actions and GHCR enabled.

## 1. Configure DNS

Create Cloudflare DNS records pointing to the VPS:

| Type | Name | Value |
| --- | --- | --- |
| A | `@` | VPS IPv4 |
| A | `*` | VPS IPv4 |

Create a Cloudflare API token with DNS edit permission limited to the selected zone.

## 2. Provision the VPS

From the repository root:

```bash
bash scripts/provision.sh
```

The script installs required Ansible collections, asks for VPS/domain details, and runs `ansible/setup.yml`.

The playbook configures:

- system updates and base packages
- UFW and fail2ban
- SSH key-only login and root login disabled
- Git, Docker Engine, and Compose plugin
- deploy user in the `docker` group
- `/opt/qresto`, ACME storage, backup and log directories
- cron jobs for health checks, backups, and certificate metrics

## 3. Fill Production Environment

SSH into the VPS as the deploy user:

```bash
ssh -p <port> qresto@<vps-ip>
```

Create the production environment file:

```bash
cp /opt/qresto/.env.bootstrap /opt/qresto/.env
nano /opt/qresto/.env
```

Replace every `replace_with_*` value. Generate strong values with:

```bash
openssl rand -base64 32
```

Keep `.env` only on the VPS. It must not be committed.

## 4. Configure GitHub Secrets

Add these secrets in `Settings -> Secrets and variables -> Actions`:

| Secret | Purpose |
| --- | --- |
| `VPS_HOST` | VPS IP or DNS name |
| `VPS_SSH_USER` | deploy user created by Ansible |
| `VPS_SSH_KEY` | private key used by GitHub Actions |
| `VPS_SSH_PORT` | SSH port, optional when using 22 |

Create a protected `production` environment in GitHub before real deployment.

## 5. Validate Locally

```bash
bash scripts/validate.sh
```

Fix any test, audit, syntax, or Compose errors before deploying.

## 6. Deploy

Open GitHub Actions, select `CI/CD Pipeline`, and run it manually from `main`.

The workflow will:

1. validate the application and infrastructure config
2. validate Ansible syntax
3. build and push the Docker image to GHCR
4. SSH into `/opt/qresto`
5. update `APP_IMAGE` in `.env`
6. pull and restart the Compose stack

## 7. Verify Production

On the VPS:

```bash
cd /opt/qresto
docker compose --env-file .env ps
curl -fsS https://example.com/live
curl -fsS https://example.com/health
```

For troubleshooting:

```bash
docker compose --env-file .env logs --tail=100 app
docker compose --env-file .env logs --tail=100 traefik
docker compose --env-file .env logs --tail=100 zabbix-server
```
