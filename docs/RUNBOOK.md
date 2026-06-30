# Runbook

## Validate

```bash
bash scripts/validate.sh
```

## Deploy

Deployments are manual from GitHub Actions:

1. Open `Actions`.
2. Select `CI/CD Pipeline`.
3. Run workflow from `main`.
4. Approve the `production` environment if protection is enabled.

## Check Services

```bash
cd /opt/qresto
docker compose --env-file .env ps
docker compose --env-file .env logs --tail=100 app
```

## Scale Application

```bash
bash /opt/qresto/scripts/traffic-mode.sh normal
bash /opt/qresto/scripts/traffic-mode.sh high
bash /opt/qresto/scripts/traffic-mode.sh status
```

## Backup

```bash
bash /opt/qresto/scripts/backup.sh
ls -lah /var/backups/qresto
```

The default backup is local. For real production, copy encrypted backups to external storage.

## TLS

```bash
bash /opt/qresto/scripts/check-acme-renew.sh
docker compose --env-file .env logs --tail=100 traefik
```

## Common Issues

| Symptom | Check |
| --- | --- |
| App returns 503 on `/ready` | MongoDB connection and `MONGODB_URI` |
| TLS certificate is missing | Cloudflare DNS token, DNS records, Traefik logs |
| Deploy cannot pull GHCR image | GitHub package visibility and Actions token permissions |
| Zabbix UI unavailable | `zabbix-db`, `zabbix-server`, and Traefik router logs |
| SSH unavailable after provisioning | Port used by UFW and the target SSH port |
